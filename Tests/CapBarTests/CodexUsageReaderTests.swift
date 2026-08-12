import XCTest
@testable import CapBar

final class CodexUsageReaderTests: XCTestCase {
    func testReadsNewestRateLimitWithoutDependingOnDirectoryOrder() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try writeLog(
            at: fixture.sessions.appendingPathComponent("older.jsonl"),
            timestamp: "2026-08-12T08:00:00Z",
            usedPercent: 12,
            modifiedAt: Date(timeIntervalSince1970: 1_786_522_000)
        )
        try writeLog(
            at: fixture.sessions.appendingPathComponent("newer.jsonl"),
            timestamp: "2026-08-12T09:00:00Z",
            usedPercent: 34,
            modifiedAt: Date(timeIntervalSince1970: 1_786_526_000)
        )

        let snapshot = CodexUsageReader(
            sessionsURL: fixture.sessions,
            authURL: fixture.auth
        ).read()

        XCTAssertEqual(snapshot.current?.usedPercent, 34)
    }

    func testFallsBackWhenNewestLogHasNoRateLimitEvent() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let older = fixture.sessions.appendingPathComponent("older.jsonl")
        try writeLog(
            at: older,
            timestamp: "2026-08-12T08:00:00Z",
            usedPercent: 21,
            modifiedAt: Date(timeIntervalSince1970: 1_786_522_000)
        )

        let newest = fixture.sessions.appendingPathComponent("newest.jsonl")
        try Data(#"{"timestamp":"2026-08-12T09:00:00Z","payload":{"type":"message"}}"#.utf8).write(to: newest)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_786_526_000)],
            ofItemAtPath: newest.path
        )

        let snapshot = CodexUsageReader(
            sessionsURL: fixture.sessions,
            authURL: fixture.auth
        ).read()

        XCTAssertEqual(snapshot.current?.usedPercent, 21)
    }

    func testReadsBackwardAcrossLargeLines() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let log = fixture.sessions.appendingPathComponent("large.jsonl")
        let event = rateLimitEvent(timestamp: "2026-08-12T09:00:00Z", usedPercent: 55)
        let largeNonEvent = #"{"payload":{"text":""# + String(repeating: "x", count: 70_000) + #""}}"#
        try Data("\(event)\n\(largeNonEvent)\n".utf8).write(to: log)

        let snapshot = CodexUsageReader(
            sessionsURL: fixture.sessions,
            authURL: fixture.auth
        ).read()

        XCTAssertEqual(snapshot.current?.usedPercent, 55)
    }

    func testStopsScanningWhenByteBudgetIsExhausted() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let log = fixture.sessions.appendingPathComponent("large.jsonl")
        let event = rateLimitEvent(timestamp: "2026-08-12T09:00:00Z", usedPercent: 55)
        let trailingData = #"{"payload":{"text":""# + String(repeating: "x", count: 80_000) + #""}}"#
        try Data("\(event)\n\(trailingData)\n".utf8).write(to: log)

        let snapshot = CodexUsageReader(
            sessionsURL: fixture.sessions,
            authURL: fixture.auth,
            scanByteLimit: 32 * 1024
        ).read()

        XCTAssertNil(snapshot.current?.usedPercent)
    }

    func testStopsScanningAfterFileLimit() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let older = fixture.sessions.appendingPathComponent("older.jsonl")
        try writeLog(
            at: older,
            timestamp: "2026-08-12T08:00:00Z",
            usedPercent: 21,
            modifiedAt: Date(timeIntervalSince1970: 1_786_522_000)
        )

        let newest = fixture.sessions.appendingPathComponent("newest.jsonl")
        try Data(#"{"timestamp":"2026-08-12T09:00:00Z","payload":{"type":"message"}}"#.utf8).write(to: newest)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_786_526_000)],
            ofItemAtPath: newest.path
        )

        let snapshot = CodexUsageReader(
            sessionsURL: fixture.sessions,
            authURL: fixture.auth,
            scanFileLimit: 1
        ).read()

        XCTAssertNil(snapshot.current?.usedPercent)
    }

    private func makeFixture() throws -> (root: URL, sessions: URL, auth: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapBarCodexUsageReaderTests-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        return (root, sessions, root.appendingPathComponent("auth.json"))
    }

    private func writeLog(
        at url: URL,
        timestamp: String,
        usedPercent: Double,
        modifiedAt: Date
    ) throws {
        try Data(rateLimitEvent(timestamp: timestamp, usedPercent: usedPercent).utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    private func rateLimitEvent(timestamp: String, usedPercent: Double) -> String {
        """
        {"timestamp":"\(timestamp)","payload":{"rate_limits":{"primary":{"used_percent":\(usedPercent),"resets_at":4102444800},"secondary":null,"plan_type":"plus"}}}
        """
    }
}
