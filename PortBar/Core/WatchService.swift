import Foundation
import Combine

@MainActor
class WatchService: ObservableObject {
    @Published var ports: [PortEntry] = []
    @Published var isWatching: Bool = false
    @Published var showAll: Bool = PortBarSettings.shared.defaultShowAll

    private var timer: Timer?
    private let scanner = PortScanner()
    private var cancellables = Set<AnyCancellable>()
    var onPortsChanged: (([PortEntry], [PortEntry]) -> Void)?

    init() {
        // Auto-refresh when showAll changes
        $showAll
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
            .store(in: &cancellables)

        // Auto-start watching if setting is on
        if PortBarSettings.shared.autoWatch {
            startWatching()
        }
    }

    func startWatching(interval: TimeInterval = 3.0) {
        isWatching = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func stopWatching() {
        isWatching = false
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard let newPorts = try? await scanner.scan(includeAll: showAll) else { return }
        let oldPorts = ports
        let oldPortNumbers = Set(oldPorts.map { $0.port })
        let newPortNumbers = Set(newPorts.map { $0.port })
        let added = newPorts.filter { !oldPortNumbers.contains($0.port) }
        let removed = oldPorts.filter { !newPortNumbers.contains($0.port) }
        ports = newPorts
        if !added.isEmpty || !removed.isEmpty {
            onPortsChanged?(added, removed)
        }
    }
}
