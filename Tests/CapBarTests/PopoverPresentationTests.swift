import AppKit
import SwiftUI
import XCTest
@testable import CapBar

final class PopoverPresentationTests: XCTestCase {
    @MainActor
    func testProviderPagesKeepTheSameSizeWithDifferentAccountAndAPIStates() async throws {
        _ = NSApplication.shared

        for apiVisible in [false, true] {
            for colorScheme in [ColorScheme.light, .dark] {
                var sizes: [NSSize] = []
                for provider in ProviderID.allCases {
                    let store = makeStore(provider: provider, apiVisible: apiVisible)
                    let view = NSHostingView(rootView: PopoverView(store: store, onQuit: {})
                        .environment(\.colorScheme, colorScheme)
                        .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)))
                    view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
                    let size = view.fittingSize
                    sizes.append(size)
                    XCTAssertEqual(size.width, 360, accuracy: 0.5)
                    XCTAssertGreaterThan(size.height, 200)

                    if let directory = ProcessInfo.processInfo.environment["CAPBAR_UI_ARTIFACT_DIR"] {
                        view.setFrameSize(size)
                        view.layoutSubtreeIfNeeded()
                        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        let url = URL(fileURLWithPath: directory, isDirectory: true)
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        try data.write(to: url.appendingPathComponent("\(provider.rawValue)-\(colorScheme)-api-\(apiVisible).png"))
                    }
                }
                XCTAssertEqual(sizes[0].height, sizes[1].height, accuracy: 0.5)
            }
        }
    }

    @MainActor
    func testMenuBarWidthStaysConstantAcrossProvidersAndDisplayModes() async {
        _ = NSApplication.shared
        var sizes: [NSSize] = []
        for provider in ProviderID.allCases {
            let store = makeStore(provider: provider, apiVisible: true)
            for mode in MenuBarDisplayMode.allCases {
                let model = StatusBarRenderModel(
                    subscriptionSnapshot: store.snapshot(for: provider),
                    apiSnapshot: store.apiSnapshot(for: provider),
                    apiMonthlyBudgetUSD: 100,
                    displayMode: mode
                )
                let view = NSHostingView(rootView: StatusBarLabel(model: model))
                sizes.append(view.fittingSize)
            }
        }
        for size in sizes {
            XCTAssertEqual(size, sizes[0])
            XCTAssertLessThanOrEqual(size.width, StatusBarLayout.itemWidth)
        }
    }

    @MainActor
    func testOutsideClicksDismissWhilePopoverControlsAndMenusStayOpen() async {
        _ = NSApplication.shared
        let popover = makeWindow()
        let statusItem = makeWindow()
        let unrelated = makeWindow()
        let child = makeWindow()
        let grandchild = makeWindow()
        let menu = makeWindow()
        menu.level = .popUpMenu
        popover.addChildWindow(child, ordered: .above)
        child.addChildWindow(grandchild, ordered: .above)
        defer {
            child.removeChildWindow(grandchild)
            popover.removeChildWindow(child)
        }

        for window in [popover, statusItem, child, grandchild, menu] {
            XCTAssertFalse(PopoverInteraction.shouldDismiss(
                for: window, popoverWindow: popover, statusItemWindow: statusItem
            ))
        }
        for window in [unrelated, nil] {
            XCTAssertTrue(PopoverInteraction.shouldDismiss(
                for: window, popoverWindow: popover, statusItemWindow: statusItem
            ))
        }
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    private func makeStore(provider: ProviderID, apiVisible: Bool) -> UsageStore {
        UsageStore(
            settings: UsageSettings(
                menuBarProvider: provider,
                refreshInterval: .manual,
                apiSectionVisible: apiVisible,
                apiMonthlyBudgetsUSD: [ProviderID.claude.rawValue: 100]
            ),
            snapshotBatch: UsageSnapshotBatch(
                subscriptions: [
                    .loading(provider: .codex),
                    ProviderSnapshot(
                        provider: .claude,
                        account: ProviderAccount(isLoggedIn: true, email: "person@example.com", detail: nil),
                        current: LimitMetric(title: "Current session", detail: "Resets in 2 hours", usedPercent: 23, resetDate: nil),
                        weekly: LimitMetric(title: "Weekly limit", detail: "Resets in 4 days", usedPercent: 67, resetDate: nil),
                        sourceDescription: "Max plan · Updated just now",
                        refreshedAt: Date(timeIntervalSince1970: 1)
                    )
                ],
                apiAccounts: [
                    .noKey(provider: .codex),
                    APIAccountSnapshot(
                        provider: .claude,
                        status: .spend(APISpendSummary(monthToDateUSD: 23.45, todayUSD: 1.23)),
                        fetchedAt: nil
                    )
                ]
            ),
            automaticallyRefreshes: false
        )
    }
}
