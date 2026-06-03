import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingView: NSHostingView<StatusBarLabel>
    private var cancellables = Set<AnyCancellable>()

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: 108)
        hostingView = NSHostingView(rootView: StatusBarLabel(snapshot: store.menuBarSnapshot))

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
        popover.contentSize = NSSize(width: 360, height: 300)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    private func bindStore() {
        store.$snapshots
            .combineLatest(store.$settings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.hostingView.rootView = StatusBarLabel(snapshot: self?.store.menuBarSnapshot ?? .loading(provider: .codex))
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
