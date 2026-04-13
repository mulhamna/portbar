import AppKit
import Combine
import SwiftUI

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    private var watchService: WatchService
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?

    init(watchService: WatchService) {
        self.watchService = watchService
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
                p.contentViewController = NSHostingController(
                    rootView: PortListPopoverView(watchService: watchService)
                )
                popover = p
            }
            popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            Task { await watchService.refresh() }
        }
    }

    // MARK: - Title

    private func updateTitle(ports: [PortEntry]) {
        guard let button = statusItem.button else { return }
        let hasZombie   = ports.contains { $0.health == .zombie }
        let hasOrphaned = ports.contains { $0.health == .orphaned }
        let color: NSColor = hasZombie ? .systemRed : hasOrphaned ? .systemYellow : .labelColor
        let prefix = watchService.isWatching ? "◉ " : ""
        button.attributedTitle = NSAttributedString(
            string: "\(prefix)⚡ \(ports.count)",
            attributes: [.foregroundColor: color]
        )
    }
}
