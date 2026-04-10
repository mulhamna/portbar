import AppKit
import Combine

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    private var watchService: WatchService
    private var cancellables = Set<AnyCancellable>()

    init(watchService: WatchService) {
        self.watchService = watchService
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        setupObservers()
        updateTitle(ports: [])
        Task { await watchService.refresh() }
    }

    private func setupObservers() {
        watchService.$ports
            .receive(on: RunLoop.main)
            .sink { [weak self] ports in
                self?.updateTitle(ports: ports)
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        watchService.$isWatching
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        PortBarSettings.shared.$displayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateTitle(ports: [PortEntry]) {
        guard let button = statusItem.button else { return }
        let count = ports.count
        let hasZombie = ports.contains { $0.health == .zombie }
        let hasOrphaned = ports.contains { $0.health == .orphaned }
        let color: NSColor = hasZombie ? .systemRed : hasOrphaned ? .systemYellow : .labelColor
        let prefix = watchService.isWatching ? "◉ " : ""
        let title = "\(prefix)⚡ \(count)"
        button.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: color])
    }

    private func rebuildMenu() {
        statusItem.menu = MenuBuilder.build(from: watchService.ports, watchService: watchService) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.watchService.refresh()
            }
        }
    }
}
