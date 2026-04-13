import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var hasUpdate: Bool = false

    private let apiURL = "https://api.github.com/repos/mulhamna/portbar/releases/latest"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private init() {}

    func check() async {
        guard let url = URL(string: apiURL) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }

        // Strip leading "v" if present (e.g. "v1.2" → "1.2")
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        latestVersion = latest
        hasUpdate = isNewer(latest, than: currentVersion)
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }
}
