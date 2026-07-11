import AppKit
import Combine
import SwiftUI

@MainActor
class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem
    private var watchService: WatchService
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?
    // ponytail: .transient is unreliable to dismiss for an LSUIElement accessory app,
    // so we close the popover ourselves on any outside click or app deactivation.
    private var outsideClickMonitor: Any?
    private var resignObserver: Any?

    init(watchService: WatchService) {
        self.watchService = watchService
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupObservers()
        updateTitle(ports: [])
        Task { await watchService.refresh() }
    }

    // MARK: - Observers

    private func setupObservers() {
        watchService.$ports
            .receive(on: RunLoop.main)
            .sink { [weak self] ports in
                self?.updateTitle(ports: ports)
                self?.rebuildUI()
            }
            .store(in: &cancellables)

        watchService.$isWatching
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildUI() }
            .store(in: &cancellables)

        PortBarSettings.shared.$displayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.popover?.close()
                self?.popover = nil
                self?.rebuildUI()
            }
            .store(in: &cancellables)

        PortBarSettings.shared.$showCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTitle(ports: self.watchService.ports)
            }
            .store(in: &cancellables)
    }

    // MARK: - Rebuild

    private func rebuildUI() {
        // Always use popover (flat list is the primary UI)
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
    }

    // MARK: - Popover (flat mode)

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let p = popover, p.isShown {
            p.close()
        } else {
            if popover == nil {
                let p = NSPopover()
                p.behavior = .transient
                p.delegate = self
                p.contentViewController = NSHostingController(
                    rootView: PortListPopoverView(watchService: watchService)
                )
                popover = p
            }
            popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            installDismissMonitors()
            Task { await watchService.refresh() }
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover?.close() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover?.close() }
        }
    }

    private func removeDismissMonitors() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
    }

    // NSPopoverDelegate — clean up whenever the popover closes (transient or manual).
    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { removeDismissMonitors() }
    }

    // MARK: - Title

    private func updateTitle(ports: [PortEntry]) {
        guard let button = statusItem.button else { return }
        let showCount = PortBarSettings.shared.showCount
        // Health tint only carries meaning next to a number; petir-only stays neutral.
        let hasZombie   = ports.contains { $0.health == .zombie }
        let hasOrphaned = ports.contains { $0.health == .orphaned }
        let color: NSColor = showCount
            ? (hasZombie ? .systemRed : hasOrphaned ? .systemYellow : .labelColor)
            : .labelColor
        button.attributedTitle = NSAttributedString(
            string: showCount ? "⚡ \(ports.count)" : "⚡",
            attributes: [.foregroundColor: color]
        )
    }
}
