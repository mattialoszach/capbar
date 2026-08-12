import XCTest
@testable import CapBar

final class StatusBarRenderModelTests: XCTestCase {
    func testIgnoresSnapshotMetadataThatIsNotRendered() {
        let first = makeSnapshot(usedPercent: 25, source: "Live", refreshedAt: Date(timeIntervalSince1970: 1))
        let second = makeSnapshot(usedPercent: 25, source: "Cached", refreshedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(makeModel(snapshot: first), makeModel(snapshot: second))
    }

    func testDetectsRenderedUsageChanges() {
        let first = makeSnapshot(usedPercent: 25, source: "Live", refreshedAt: Date(timeIntervalSince1970: 1))
        let second = makeSnapshot(usedPercent: 26, source: "Live", refreshedAt: Date(timeIntervalSince1970: 1))

        XCTAssertNotEqual(makeModel(snapshot: first), makeModel(snapshot: second))
    }

    private func makeModel(snapshot: ProviderSnapshot) -> StatusBarRenderModel {
        StatusBarRenderModel(
            subscriptionSnapshot: snapshot,
            apiSnapshot: .noKey(provider: snapshot.provider),
            apiMonthlyBudgetUSD: nil,
            displayMode: .subscription,
            usesExpandedLayout: false
        )
    }

    private func makeSnapshot(usedPercent: Double, source: String, refreshedAt: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex,
            account: .loggedOut,
            current: LimitMetric(
                title: "Current session",
                detail: "5 hour usage limit",
                usedPercent: usedPercent,
                resetDate: nil
            ),
            weekly: nil,
            sourceDescription: source,
            refreshedAt: refreshedAt
        )
    }
}
