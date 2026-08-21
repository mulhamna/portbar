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
        // Always use popover (flat list is the primary UI); right-click pops its own
        // menu up, see showContextMenu.
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    // MARK: - Right-click menu

    private func showContextMenu(_ sender: NSStatusBarButton) {
        popover?.close()
        let menu = NSMenu()
        menu.addItem(item(watchService.isWatching ? "Stop Watching" : "Start Watching",
                          #selector(toggleWatch)))
        menu.addItem(item("Refresh Now", #selector(refreshNow)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PortBar",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // ponytail: popped up directly rather than assigned to statusItem.menu — an
        // attached menu would swallow the left click that opens the popover.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleWatch() {
        if watchService.isWatching { watchService.stopWatching() } else { watchService.startWatching() }
    }

    @objc private func refreshNow() {
        Task { await watchService.refresh() }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show(watchService: watchService)
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
            if let win = sender.window {
                let onScreen = win.convertToScreen(sender.convert(sender.bounds, to: nil))
                let vf = (win.screen ?? NSScreen.main)?.visibleFrame ?? onScreen
                // ponytail: NSPopover slides its own frame along the edge to stay on
                // screen and keeps the arrow on the anchor, so the budget is the whole
                // screen — not the symmetric room under the icon. Capping to room*2
                // squeezed the panel to nothing whenever the icon sat off-centre.
                PortBarSettings.shared.maxPopoverWidth = max(480, vf.width - 24)
                // Everything below the icon, less a margin so the popover never
                // reaches the bottom edge of the screen.
                PortBarSettings.shared.maxPopoverHeight = max(360, onScreen.minY - vf.minY - 24)
            }
            // Size the frame before showing: AppKit anchors from the current content
            // size, and the SwiftUI relayout for the caps above lands a runloop later —
            // so without this the first open is positioned from the previous size.
            popover?.contentSize.width = PortBarSettings.shared.renderWidth
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
