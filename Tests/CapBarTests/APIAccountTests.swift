import XCTest
@testable import CapBar

final class APIAccountTests: XCTestCase {
    func testAnthropicCostPageConvertsCentsAndDetectsToday() throws {
        let json = Data(
            """
            {
              "data": [
                {
                  "starting_at": "2026-07-01T00:00:00Z",
                  "ending_at": "2026-07-02T00:00:00Z",
                  "results": [
                    { "amount": "123.45", "currency": "USD" },
                    { "amount": "76.55", "currency": "USD" }
                  ]
                },
                {
                  "starting_at": "2026-07-02T00:00:00Z",
                  "ending_at": "2026-07-03T00:00:00Z",
                  "results": [
                    { "amount": "300", "currency": "USD" }
                  ]
                }
              ],
              "has_more": false,
              "next_page": null
            }
            """.utf8
        )
        let now = try XCTUnwrap(DateParser.parse("2026-07-02T12:00:00Z"))

        let page = try XCTUnwrap(APISpendParser.anthropicPage(from: json, now: now))

        XCTAssertEqual(page.totalUSD, 5.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(page.todayUSD), 3.0, accuracy: 0.0001)
        XCTAssertNil(page.nextPage)
    }

    func testAnthropicCostPagePropagatesNextPage() throws {
        let json = Data(
            """
            {
              "data": [],
              "has_more": true,
              "next_page": "page_xyz"
            }
            """.utf8
        )

        let page = try XCTUnwrap(APISpendParser.anthropicPage(from: json, now: Date()))

        XCTAssertEqual(page.nextPage, "page_xyz")
        XCTAssertEqual(page.totalUSD, 0)
        XCTAssertNil(page.todayUSD)
    }

    func testOpenAICostPageSumsDollarsAndDetectsToday() throws {
        let now = try XCTUnwrap(DateParser.parse("2026-07-02T12:00:00Z"))
        let dayStart = Int(now.timeIntervalSince1970) - 12 * 3600
        let dayEnd = dayStart + 24 * 3600
        let json = Data(
            """
            {
              "object": "page",
              "data": [
                {
                  "object": "bucket",
                  "start_time": \(dayStart - 86400),
                  "end_time": \(dayStart),
                  "results": [
                    { "object": "organization.costs.result", "amount": { "value": 1.25, "currency": "usd" } }
                  ]
                },
                {
                  "object": "bucket",
                  "start_time": \(dayStart),
                  "end_time": \(dayEnd),
                  "results": [
                    { "object": "organization.costs.result", "amount": { "value": "0.75", "currency": "usd" } }
                  ]
                }
              ],
              "has_more": false,
              "next_page": null
            }
            """.utf8
        )

        let page = try XCTUnwrap(APISpendParser.openAIPage(from: json, now: now))

        XCTAssertEqual(page.totalUSD, 2.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(page.todayUSD), 0.75, accuracy: 0.0001)
        XCTAssertNil(page.nextPage)
    }

    func testOpenAICostPageHandlesEmptyBuckets() throws {
        let json = Data(
            """
            {
              "object": "page",
              "data": [
                { "object": "bucket", "start_time": 1, "end_time": 2, "results": [] }
              ],
              "has_more": false,
              "next_page": null
            }
            """.utf8
        )

        let page = try XCTUnwrap(APISpendParser.openAIPage(from: json, now: Date()))

        XCTAssertEqual(page.totalUSD, 0)
        XCTAssertNil(page.todayUSD)
    }

    func testStartOfMonthUTC() throws {
        let date = try XCTUnwrap(DateParser.parse("2026-07-15T18:30:00Z"))
        let monthStart = APIAccountReader.startOfMonthUTC(for: date)

        XCTAssertEqual(monthStart, DateParser.parse("2026-07-01T00:00:00Z"))
    }

    func testStartOfNextDayUTC() throws {
        let date = try XCTUnwrap(DateParser.parse("2026-07-02T12:00:00Z"))

        XCTAssertEqual(APIAccountReader.startOfNextDayUTC(for: date), DateParser.parse("2026-07-03T00:00:00Z"))
    }

    func testOpenAICostPageDetectsCurrentUTCBucket() throws {
        let now = try XCTUnwrap(DateParser.parse("2026-07-02T11:00:00Z"))
        let json = Data(
            """
            {
              "object": "page",
              "data": [
                {
                  "object": "bucket",
                  "start_time": 1782950400,
                  "end_time": 1783036800,
                  "results": [
                    { "object": "organization.costs.result", "amount": { "value": 2.29188675, "currency": "usd" } }
                  ]
                }
              ],
              "has_more": false,
              "next_page": null
            }
            """.utf8
        )

        let page = try XCTUnwrap(APISpendParser.openAIPage(from: json, now: now))

        XCTAssertEqual(page.totalUSD, 2.29188675, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(page.todayUSD), 2.29188675, accuracy: 0.0000001)
    }

    func testSpendCacheExpiresAfterOneDay() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertTrue(
            APISpendRetryPolicy.canUseCache(
                fetchedAt: now.addingTimeInterval(-(24 * 60 * 60)),
                now: now
            )
        )
        XCTAssertFalse(
            APISpendRetryPolicy.canUseCache(
                fetchedAt: now.addingTimeInterval(-(24 * 60 * 60) - 1),
                now: now
            )
        )
    }

    func testSpendSummaryFormatting() {
        let summary = APISpendSummary(monthToDateUSD: 12.349, todayUSD: nil)

        XCTAssertEqual(summary.monthToDateText, "$12.35")
        XCTAssertEqual(summary.todayText, "$0.00")
    }

    func testCompactUSDUsesFourSignificantDigitsForLargeValues() {
        XCTAssertEqual(Formatters.compactUSD(999.99), "$999.99")
        XCTAssertEqual(Formatters.compactUSD(1_000), "$1.000k")
        XCTAssertEqual(Formatters.compactUSD(10_000), "$10.00k")
        XCTAssertEqual(Formatters.compactUSD(100_000), "$100.0k")
        XCTAssertEqual(Formatters.compactUSD(1_234_567), "$1.235M")
        XCTAssertEqual(Formatters.compactUSD(1_000_000_000), "$1.000B")
    }

    func testMenuBarUSDUsesAtMostThreeSignificantDigits() {
        XCTAssertEqual(Formatters.menuBarUSD(2.29188675), "$2.29")
        XCTAssertEqual(Formatters.menuBarUSD(12.349), "$12.3")
        XCTAssertEqual(Formatters.menuBarUSD(123.45), "$123")
        XCTAssertEqual(Formatters.menuBarUSD(999.99), "$1k")
        XCTAssertEqual(Formatters.menuBarUSD(1_234), "$1.23k")
        XCTAssertEqual(Formatters.menuBarUSD(12_345), "$12.3k")
        XCTAssertEqual(Formatters.menuBarUSD(1_234_567), "$1.23M")
    }

    func testMockSpendSummaryReadsEnvironmentValues() throws {
        let summary = try XCTUnwrap(
            APIAccountReader.mockSpendSummary(
                environment: [
                    "CAPBAR_MOCK_API_TODAY_USD": "1_000",
                    "CAPBAR_MOCK_API_MONTH_USD": "$1,234,567"
                ]
            )
        )

        XCTAssertEqual(try XCTUnwrap(summary.todayUSD), 1_000, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(summary.monthToDateUSD), 1_234_567, accuracy: 0.0001)
        XCTAssertNil(APIAccountReader.mockSpendSummary(environment: [:]))
    }

    func testOpenAICreditGrantsParsing() {
        let json = Data(
            #"{"object":"credit_summary","total_granted":120.0,"total_used":104.5,"total_available":15.5,"grants":{"data":[]}}"#.utf8
        )

        let credits = APISpendParser.openAICredits(from: json)

        XCTAssertEqual(credits?.remaining ?? -1, 15.5, accuracy: 0.0001)
        XCTAssertEqual(credits?.granted ?? -1, 120.0, accuracy: 0.0001)
        XCTAssertNil(APISpendParser.openAICredits(from: Data("{}".utf8)))
    }

    func testSpendSummaryCreditsOnly() {
        let summary = APISpendSummary(
            monthToDateUSD: nil,
            todayUSD: nil,
            creditsRemainingUSD: 15.5,
            creditsGrantedUSD: 120
        )

        XCTAssertFalse(summary.hasSpend)
        XCTAssertTrue(summary.hasCredits)
        XCTAssertEqual(summary.creditsRemainingText, "$15.50")
        XCTAssertEqual(summary.creditsGrantedText, "$120.00")
    }

    func testOpenAIMonthlyLimitParsing() {
        let withHardLimit = Data(
            #"{"object":"billing_subscription","has_payment_method":true,"hard_limit_usd":120.0,"soft_limit_usd":100.0,"system_hard_limit_usd":500.0}"#.utf8
        )
        let systemOnly = Data(
            #"{"object":"billing_subscription","system_hard_limit_usd":500.0}"#.utf8
        )
        let zeroLimit = Data(
            #"{"hard_limit_usd":0}"#.utf8
        )

        XCTAssertEqual(APISpendParser.openAIMonthlyLimit(from: withHardLimit) ?? -1, 120.0, accuracy: 0.0001)
        XCTAssertEqual(APISpendParser.openAIMonthlyLimit(from: systemOnly) ?? -1, 500.0, accuracy: 0.0001)
        XCTAssertNil(APISpendParser.openAIMonthlyLimit(from: zeroLimit))
        XCTAssertNil(APISpendParser.openAIMonthlyLimit(from: Data("not json".utf8)))
    }

    func testMonthlyBudgetSettingsRoundTripAndBackwardsCompatibility() throws {
        // Old persisted settings without the budgets field still decode.
        let legacy = Data(
            #"{"menuBarProvider":"claude","refreshInterval":300,"lowUsageColorsEnabled":false}"#.utf8
        )
        let legacySettings = try JSONDecoder().decode(UsageSettings.self, from: legacy)
        XCTAssertTrue(legacySettings.apiSectionVisible)
        XCTAssertTrue(legacySettings.apiMonthlyBudgetsUSD.isEmpty)

        var settings = UsageSettings.default
        settings.apiSectionVisible = false
        settings.apiMonthlyBudgetsUSD["claude"] = 250
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UsageSettings.self, from: encoded)
        XCTAssertFalse(decoded.apiSectionVisible)
        XCTAssertEqual(decoded.apiMonthlyBudgetUSD(for: .claude) ?? -1, 250, accuracy: 0.0001)
        XCTAssertNil(decoded.apiMonthlyBudgetUSD(for: .codex))
    }

    func testErrorMessageParsing() {
        let anthropic = Data(
            #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8
        )
        let openAI = Data(
            #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8
        )
        let garbage = Data("not json".utf8)

        XCTAssertEqual(APIAccountReader.errorMessage(from: anthropic), "invalid x-api-key")
        XCTAssertEqual(APIAccountReader.errorMessage(from: openAI), "Incorrect API key provided")
        XCTAssertNil(APIAccountReader.errorMessage(from: garbage))
    }

    func testAPIKeyStoreFileRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapBarTests-\(UUID().uuidString)/api-keys.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(APIKeyStore.key(for: .claude, fileURL: fileURL))

        XCTAssertTrue(APIKeyStore.setKey("  sk-ant-admin01-test  ", for: .claude, fileURL: fileURL))
        XCTAssertTrue(APIKeyStore.setKey("sk-admin-test", for: .codex, fileURL: fileURL))

        XCTAssertEqual(APIKeyStore.key(for: .claude, fileURL: fileURL), "sk-ant-admin01-test")
        XCTAssertEqual(APIKeyStore.key(for: .codex, fileURL: fileURL), "sk-admin-test")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.int16Value, 0o600)

        APIKeyStore.deleteKey(for: .claude, fileURL: fileURL)
        XCTAssertNil(APIKeyStore.key(for: .claude, fileURL: fileURL))
        XCTAssertEqual(APIKeyStore.key(for: .codex, fileURL: fileURL), "sk-admin-test")

        XCTAssertFalse(APIKeyStore.setKey("   ", for: .claude, fileURL: fileURL))
    }

    func testPlatformNames() {
        XCTAssertEqual(ProviderID.codex.platformName, "OpenAI")
        XCTAssertEqual(ProviderID.claude.platformName, "Anthropic")
    }
}
