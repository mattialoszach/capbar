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
}
