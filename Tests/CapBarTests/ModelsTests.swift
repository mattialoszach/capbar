import XCTest
@testable import CapBar

final class ModelsTests: XCTestCase {
    func testProviderRotationDefaultsToOff() throws {
        let data = Data(
            #"{"menuBarProvider":"claude","refreshInterval":300,"lowUsageColorsEnabled":false}"#.utf8
        )

        let settings = try JSONDecoder().decode(UsageSettings.self, from: data)

        XCTAssertEqual(settings.providerRotationInterval, .off)
    }

    func testProviderRotationIntervals() {
        XCTAssertNil(ProviderRotationInterval.off.timeInterval)
        XCTAssertEqual(ProviderRotationInterval.fiveSeconds.timeInterval, 5)
        XCTAssertEqual(ProviderRotationInterval.tenSeconds.timeInterval, 10)
    }

    func testNextProviderCyclesThroughAllProviders() {
        XCTAssertEqual(ProviderID.codex.next, .claude)
        XCTAssertEqual(ProviderID.claude.next, .codex)
    }

    func testClaudeRateLimitBackoffIsBounded() {
        XCTAssertEqual(ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 1, retryAfter: nil), 15 * 60)
        XCTAssertEqual(ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 2, retryAfter: nil), 30 * 60)
        XCTAssertEqual(ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 3, retryAfter: nil), 60 * 60)
        XCTAssertEqual(ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 4, retryAfter: nil), 2 * 60 * 60)
        XCTAssertEqual(ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 8, retryAfter: nil), 2 * 60 * 60)
    }

    func testClaudeRateLimitBackoffHonorsLongerRetryAfter() {
        XCTAssertEqual(
            ClaudeUsageRetryPolicy.rateLimitDelay(failureCount: 1, retryAfter: 45 * 60),
            45 * 60
        )
    }

    func testClaudeCacheExpiresAfterOneDay() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertTrue(
            ClaudeUsageRetryPolicy.canUseCache(
                fetchedAt: now.addingTimeInterval(-(24 * 60 * 60)),
                now: now
            )
        )
        XCTAssertFalse(
            ClaudeUsageRetryPolicy.canUseCache(
                fetchedAt: now.addingTimeInterval(-(24 * 60 * 60) - 1),
                now: now
            )
        )
    }
}
