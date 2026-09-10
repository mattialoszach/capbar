import XCTest
@testable import CapBar

final class CodexLiveUsageReaderTests: XCTestCase {
    func testConsecutiveRefreshesReadFreshUsageWithoutCacheDelay() async throws {
        let responseURL = try temporaryResponseURL()
        let reader = liveReader(responseURL: responseURL)
        try writeUsage(current: 12, weekly: 34, to: responseURL)

        let first = await reader.read()
        XCTAssertEqual(first.current?.usedPercent, 12)
        XCTAssertEqual(first.weekly?.usedPercent, 34)

        try writeUsage(current: 56, weekly: 78, to: responseURL)
        let second = await reader.read()
        XCTAssertEqual(second.current?.usedPercent, 56)
        XCTAssertEqual(second.weekly?.usedPercent, 78)
        XCTAssertEqual(second.sourceDescription, "Codex live limits")
        XCTAssertGreaterThanOrEqual(second.refreshedAt, first.refreshedAt)
    }

    func testRefreshRechecksAccountWithoutAnAuthFileChange() async throws {
        let responseURL = try temporaryResponseURL()
        let reader = liveReader(responseURL: responseURL)
        try writeUsage(current: 12, weekly: 34, to: responseURL)
        let loggedIn = await reader.read()
        XCTAssertTrue(loggedIn.account.isLoggedIn)

        try Data(#"{"account":null}"#.utf8).write(to: responseURL)
        let loggedOut = await reader.read()
        XCTAssertFalse(loggedOut.account.isLoggedIn)
        XCTAssertNil(loggedOut.current)
        XCTAssertNil(loggedOut.weekly)
        XCTAssertEqual(loggedOut.sourceDescription, "Login required")
    }

    func testRefreshFallsBackOnFailureAndRetriesOnTheNextRefresh() async throws {
        let responseURL = try temporaryResponseURL()
        let reader = liveReader(responseURL: responseURL)
        try writeUsage(current: 12, weekly: 34, to: responseURL)
        let first = await reader.read()
        XCTAssertEqual(first.current?.usedPercent, 12)

        try FileManager.default.removeItem(at: responseURL)
        let fallback = await reader.read()
        XCTAssertEqual(fallback.sourceDescription, "No Codex sessions found")
        XCTAssertNil(fallback.current)

        try writeUsage(current: 56, weekly: 78, to: responseURL)
        let recovered = await reader.read()
        XCTAssertEqual(recovered.current?.usedPercent, 56)
        XCTAssertEqual(recovered.weekly?.usedPercent, 78)
        XCTAssertEqual(recovered.sourceDescription, "Codex live limits")
    }

    func testChoosesCodexBucketOverOtherQuota() throws {
        let response = try decodeLimits("""
        {"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":99}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":23,"windowDurationMins":300,"resetsAt":4102444800},
         "secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":4102444800}}}}
        """)
        XCTAssertEqual(response.codexLimits?.primary?.usedPercent, 23)
        XCTAssertEqual(response.codexLimits?.secondary?.usedPercent, 42)
        XCTAssertEqual(response.codexLimits?.primary?.windowMinutes, 300)
    }

    func testOtherBucketAloneIsNotAccountQuota() throws {
        let response = try decodeLimits(#"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":99}}}"#)
        XCTAssertNil(response.codexLimits)
    }

    func testLegacyResponseWithoutBucketIDStillWorks() throws {
        let response = try decodeLimits(#"{"rateLimits":{"primary":{"usedPercent":17},"secondary":null}}"#)
        XCTAssertEqual(response.codexLimits?.primary?.usedPercent, 17)
    }

    func testAppServerHandshakeAndUsageWithNotificationsAndLargeStderr() throws {
        let script = """
        IFS= read -r line
        case "$line" in *'"method":"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":0,"result":{}}'
        IFS= read -r line
        case "$line" in *'"method":"initialized"'*) ;; *) exit 1 ;; esac
        IFS= read -r line
        case "$line" in *'account/read'*) ;; *) exit 1 ;; esac
        /usr/bin/awk 'BEGIN { for (i=0;i<5000;i++) print "diagnostic output" }' >&2
        printf '%s\\n' '{"method":"account/updated","params":{}}' '{"id":1,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"plus"}}}'
        IFS= read -r line
        case "$line" in *'account/rateLimits/read'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"resetsAt":4102444800}}}}'
        """
        let usage = try client(script: script).read()
        let snapshot = usage.snapshot(refreshedAt: Date())
        XCTAssertTrue(snapshot.account.isLoggedIn)
        XCTAssertEqual(snapshot.account.email, "test@example.com")
        XCTAssertEqual(snapshot.current?.usedPercent, 12)
    }

    func testAPIKeyAccountDoesNotRequestSubscriptionLimits() throws {
        let script = """
        IFS= read -r line
        printf '%s\\n' '{"id":0,"result":{}}'
        IFS= read -r line
        IFS= read -r line
        printf '%s\\n' '{"id":1,"result":{"account":{"type":"apiKey"}}}'
        """
        let snapshot = try client(script: script).read().snapshot(refreshedAt: Date())
        XCTAssertTrue(snapshot.account.isLoggedIn)
        XCTAssertNil(snapshot.current)
        XCTAssertTrue(snapshot.sourceDescription.contains("ChatGPT login"))
    }

    func testUnavailableLimitsKeepConfirmedAccountWithoutHistoricalUsage() throws {
        let script = """
        IFS= read -r line
        printf '%s\\n' '{"id":0,"result":{}}'
        IFS= read -r line
        IFS= read -r line
        printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","planType":"pro"}}}'
        IFS= read -r line
        printf '%s\\n' '{"id":2,"error":{"code":-32000,"message":"unavailable"}}'
        """
        let snapshot = try client(script: script).read().snapshot(refreshedAt: Date())
        XCTAssertTrue(snapshot.account.isLoggedIn)
        XCTAssertNil(snapshot.current)
        XCTAssertEqual(snapshot.sourceDescription, "Codex usage unavailable")
    }

    func testStalledCLIIsTerminatedWithinDeadline() {
        let start = Date()
        XCTAssertThrowsError(try client(script: "while IFS= read -r line; do :; done", timeout: 0.2).read())
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testEarlyCLIExitDoesNotCrashOrHang() {
        XCTAssertThrowsError(try client(script: "exit 1").read())
    }

    func testInstalledCodexSmokeTestWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["CAPBAR_TEST_LIVE_CODEX"] == "1" else {
            throw XCTSkip("Set CAPBAR_TEST_LIVE_CODEX=1 for the installed CLI integration check")
        }
        let usage = try CodexAppServerClient().read()
        print("Codex integration: auth=\(usage.account?.type ?? "logged out"), usage available=\(usage.limits != nil)")
    }

    private func client(script: String, timeout: TimeInterval = 3) -> CodexAppServerClient {
        CodexAppServerClient(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], timeout: timeout)
    }

    private func temporaryResponseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("response.json")
    }

    private func liveReader(responseURL: URL) -> CodexLiveUsageReader {
        let directory = responseURL.deletingLastPathComponent()
        return CodexLiveUsageReader(
            usageLoader: {
                let data = try Data(contentsOf: responseURL)
                let decoder = JSONDecoder()
                return CodexAccountUsage(
                    account: try decoder.decode(CodexAccountResponse.self, from: data).account,
                    limits: try decoder.decode(CodexRateLimitsResponse.self, from: data).codexLimits
                )
            },
            fallbackReader: CodexUsageReader(
                sessionsURL: directory.appendingPathComponent("sessions"),
                authURL: directory.appendingPathComponent("auth.json")
            )
        )
    }

    private func writeUsage(current: Int, weekly: Int, to url: URL) throws {
        let response = """
        {"account":{"type":"chatgpt","email":"test@example.com","planType":"plus"},
         "rateLimits":{"limitId":"codex","primary":{"usedPercent":\(current)},
         "secondary":{"usedPercent":\(weekly)}}}
        """
        try Data(response.utf8).write(to: url)
    }

    private func decodeLimits(_ json: String) throws -> CodexRateLimitsResponse {
        try JSONDecoder().decode(CodexRateLimitsResponse.self, from: Data(json.utf8))
    }
}
