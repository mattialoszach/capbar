import XCTest
@testable import CapBar

final class ClaudeUsageReaderTests: XCTestCase {
    func testAccountSwitchDoesNotReuseUsageOnFailureOrNextRead() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let first = reader(cache: cache, token: "account-a", result: .success(try usage(percent: 17)))
        let initial = await first.read()
        XCTAssertEqual(initial.current?.usedPercent, 17)

        let second = reader(cache: cache, token: "account-b", result: .rateLimited(retryAfter: nil))
        let switched = await second.read()
        XCTAssertNil(switched.current?.usedPercent)
        // The failed request must not re-tag account A's cached usage as B's.
        let subsequent = await second.read()
        XCTAssertNil(subsequent.current?.usedPercent)
    }

    func testLogoutClearsCachedUsage() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        _ = await reader(cache: cache, token: "account-a", result: .success(try usage(percent: 32))).read()
        let loggedOut = await reader(cache: cache, token: nil, result: .unavailable).read()
        XCTAssertFalse(loggedOut.account.isLoggedIn)
        XCTAssertNil(loggedOut.current?.usedPercent)
        XCTAssertFalse(cache.fileExists)
    }

    func testManualRefreshBypassesSuccessfulUsageCooldown() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        _ = await reader(cache: cache, token: "account-a", result: .success(try usage(percent: 45))).read()
        let next = reader(cache: cache, token: "account-a", result: .success(try usage(percent: 99)))
        let snapshot = await next.read(force: true)
        XCTAssertEqual(snapshot.current?.usedPercent, 99)
        XCTAssertEqual(snapshot.sourceDescription, "Claude OAuth usage")
    }

    func testManualRefreshStillHonorsRateLimitBackoff() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        _ = await reader(cache: cache, token: "account-a", result: .success(try usage(percent: 45))).read()
        _ = await reader(cache: cache, token: "account-a", result: .rateLimited(retryAfter: 600)).read(force: true)

        let snapshot = await reader(
            cache: cache,
            token: "account-a",
            result: .success(try usage(percent: 99))
        ).read(force: true)
        XCTAssertEqual(snapshot.current?.usedPercent, 45)
        XCTAssertTrue(snapshot.sourceDescription.contains("Cached"))
    }

    func testAutomaticUsageCooldownMatchesShortestRefreshInterval() {
        XCTAssertEqual(ClaudeUsageRetryPolicy.minimumFetchInterval, 30)
    }

    func testLegacyCacheWithoutFingerprintIsNotReused() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = """
        {"usage":{"five_hour":{"utilization":70}},"fetchedAt":\(Date().timeIntervalSinceReferenceDate),"rateLimitFailureCount":0}
        """
        try Data(legacy.utf8).write(to: cache)
        let snapshot = await reader(cache: cache, token: "account-b", result: .unavailable).read()
        XCTAssertNil(snapshot.current?.usedPercent)
    }

    func testExpiredCredentialsDoNotCallUsageEndpoint() async throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let credentials = credentials(token: "expired", expiresAt: .distantPast)
        let usage = try usage(percent: 99)
        let snapshot = await ClaudeUsageReader(
            cacheURL: cache,
            credentialsLoader: { credentials },
            usageLoader: { _ in .success(usage) }
        ).read()
        XCTAssertNil(snapshot.current?.usedPercent)
        XCTAssertEqual(snapshot.current?.detail, "Open Claude to refresh login")
    }

    func testRetryAfterAcceptsSecondsAndHTTPDate() throws {
        let now = try XCTUnwrap(DateParser.parse("2026-09-09T12:00:00Z"))
        XCTAssertEqual(ClaudeUsageRetryPolicy.retryAfter("120", now: now), 120)
        XCTAssertEqual(ClaudeUsageRetryPolicy.retryAfter("Wed, 09 Sep 2026 13:00:00 GMT", now: now), 3600)
        XCTAssertNil(ClaudeUsageRetryPolicy.retryAfter("invalid", now: now))
        XCTAssertNil(ClaudeUsageRetryPolicy.retryAfter("inf", now: now))
        XCTAssertNil(ClaudeUsageRetryPolicy.retryAfter("-1", now: now))
        XCTAssertFalse(ClaudeUsageRetryPolicy.canUseCache(fetchedAt: now.addingTimeInterval(60), now: now))
    }

    func testKeychainServiceFollowsConfigurationNamespace() {
        XCTAssertEqual(ClaudeUsageReader.keychainServiceName(environment: [:]), "Claude Code-credentials")
        let custom = ClaudeUsageReader.keychainServiceName(environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-work"])
        XCTAssertNotEqual(custom, "Claude Code-credentials")
        XCTAssertEqual(custom, ClaudeUsageReader.keychainServiceName(environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/claude-work"]))
        XCTAssertEqual(
            ClaudeUsageReader.keychainServiceName(environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": ""]),
            "Claude Code-credentials"
        )
        XCTAssertEqual(
            ClaudeUsageReader.keychainServiceName(environment: ["CLAUDE_CONFIG_DIR": "/tmp/caf\u{00e9}"]),
            ClaudeUsageReader.keychainServiceName(environment: ["CLAUDE_CONFIG_DIR": "/tmp/cafe\u{0301}"])
        )
    }

    func testInstalledClaudeSmokeTestWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CAPBAR_TEST_LIVE_CLAUDE"] == "1" else {
            throw XCTSkip("Set CAPBAR_TEST_LIVE_CLAUDE=1 for the installed Claude integration check")
        }
        let snapshot = await ClaudeUsageReader().read()
        print("Claude integration: logged in=\(snapshot.account.isLoggedIn), usage available=\(snapshot.current?.usedPercent != nil), source=\(snapshot.sourceDescription), detail=\(snapshot.current?.detail ?? "none")")
        XCTAssertTrue(snapshot.account.isLoggedIn)
        XCTAssertNotNil(snapshot.current?.usedPercent)
    }

    private func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CapBarClaudeTests-\(UUID().uuidString)/usage.json")
    }

    private func reader(cache: URL, token: String?, result: ClaudeUsageFetchResult) -> ClaudeUsageReader {
        let credentials = token.map { self.credentials(token: $0) }
        return ClaudeUsageReader(cacheURL: cache, credentialsLoader: { credentials }, usageLoader: { _ in result })
    }

    private func credentials(token: String, expiresAt: Date = .distantFuture) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(accessToken: token, refreshToken: nil, subscriptionType: "pro", rateLimitTier: nil, expiresAt: expiresAt)
    }

    private func usage(percent: Double) throws -> ClaudeOAuthUsage {
        try JSONDecoder().decode(ClaudeOAuthUsage.self, from: Data("""
        {"five_hour":{"utilization":\(percent),"resets_at":"2100-01-01T00:00:00Z"}}
        """.utf8))
    }
}
