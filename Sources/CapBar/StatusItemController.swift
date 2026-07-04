import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingView: NSHostingView<StatusBarLabel>
    private var cancellables = Set<AnyCancellable>()
    private var providerRotationTimer: Timer?

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(
            withLength: Self.statusItemLength(for: store.menuBarDisplayMode)
        )
        hostingView = NSHostingView(
            rootView: StatusBarLabel(
                subscriptionSnapshot: store.menuBarSnapshot,
                apiSnapshot: store.menuBarAPISnapshot,
                apiMonthlyBudgetUSD: store.menuBarAPIMonthlyBudgetUSD,
                displayMode: store.menuBarDisplayMode
            )
        )
        super.init()

        configureStatusButton()
        configurePopover()
        bindStore()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "CapBar"

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: PopoverView(store: store, onQuit: { [weak self] in
                self?.quitApplication()
            })
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func bindStore() {
        store.$snapshots
            .combineLatest(store.$apiSnapshots, store.$settings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarLabel()
            }
            .store(in: &cancellables)

        store.$settings
            .map(\.providerRotationInterval)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureProviderRotationTimer()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closePopoverIfShown()
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarLabel() {
        let statusItemLength = Self.statusItemLength(for: store.menuBarDisplayMode)
        if statusItem.length != statusItemLength {
            statusItem.length = statusItemLength
        }
        hostingView.rootView = StatusBarLabel(
            subscriptionSnapshot: store.menuBarSnapshot,
            apiSnapshot: store.menuBarAPISnapshot,
            apiMonthlyBudgetUSD: store.menuBarAPIMonthlyBudgetUSD,
            displayMode: store.menuBarDisplayMode
        )
    }

    private static func statusItemLength(for displayMode: MenuBarDisplayMode) -> CGFloat {
        96
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            pauseProviderRotation()
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        configureProviderRotationTimer()
    }

    private func quitApplication() {
        popover.performClose(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func closePopoverIfShown() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func configureProviderRotationTimer() {
        pauseProviderRotation()

        guard !popover.isShown,
              let interval = store.settings.providerRotationInterval.timeInterval,
              ProviderID.allCases.count > 1 else {
            return
        }

        providerRotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.rotateMenuBarProvider()
            }
        }
    }

    private func pauseProviderRotation() {
        providerRotationTimer?.invalidate()
        providerRotationTimer = nil
    }
}
