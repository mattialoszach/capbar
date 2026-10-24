import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingView: NSHostingView<StatusBarLabel>
    private var renderedModel: StatusBarRenderModel
    private var cancellables = Set<AnyCancellable>()
    private var providerRotationTimer: Timer?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: StatusBarLayout.itemWidth)
        let initialModel = StatusBarRenderModel(
            subscriptionSnapshot: store.menuBarSnapshot,
            apiSnapshot: store.menuBarAPISnapshot,
            apiMonthlyBudgetUSD: store.menuBarAPIMonthlyBudgetUSD,
            displayMode: store.menuBarDisplayMode
        )
        renderedModel = initialModel
        hostingView = NSHostingView(rootView: StatusBarLabel(model: initialModel))
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
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
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
        store.$snapshotBatch
            .combineLatest(store.$settings)
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
        let model = StatusBarRenderModel(
            subscriptionSnapshot: store.menuBarSnapshot,
            apiSnapshot: store.menuBarAPISnapshot,
            apiMonthlyBudgetUSD: store.menuBarAPIMonthlyBudgetUSD,
            displayMode: store.menuBarDisplayMode
        )
        guard model != renderedModel else { return }
        renderedModel = model

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            hostingView.rootView = StatusBarLabel(model: model)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            pauseProviderRotation()
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Opening and content resizing stay instant; only dismissal animates.
            popover.animates = false
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        startEventMonitoring()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        popover.animates = true
        return true
    }

    func popoverWillClose(_ notification: Notification) {
        stopEventMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitoring()
        popover.animates = false
        configureProviderRotationTimer()
    }

    private func startEventMonitoring() {
        stopEventMonitoring()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            // AppKit delivers event monitor callbacks on the main thread.
            MainActor.assumeIsolated {
                self?.closePopoverIfShown()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents.union(.keyDown)) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return false }

                // Native menus and sheets must keep handling their own input.
                if event.type == .keyDown {
                    if event.keyCode == 53, event.window === self.popover.contentViewController?.view.window {
                        self.closePopoverIfShown()
                        return true
                    }
                } else if PopoverInteraction.shouldDismiss(
                    for: event.window,
                    popoverWindow: self.popover.contentViewController?.view.window,
                    statusItemWindow: self.statusItem.button?.window
                ) {
                    self.closePopoverIfShown()
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
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

enum PopoverInteraction {
    @MainActor
    static func shouldDismiss(
        for eventWindow: NSWindow?,
        popoverWindow: NSWindow?,
        statusItemWindow: NSWindow?
    ) -> Bool {
        guard let eventWindow else { return true }
        if eventWindow === statusItemWindow || eventWindow.level == .popUpMenu {
            return false
        }

        var window: NSWindow? = eventWindow
        while let current = window {
            if current === popoverWindow { return false }
            window = current.parent ?? current.sheetParent
        }
        return true
    }
}
