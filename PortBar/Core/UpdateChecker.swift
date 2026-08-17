import Foundation
import AppKit

enum UpdateState: Equatable {
    case idle
    case running
    case failed(String)
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var hasUpdate: Bool = false
    @Published var state: UpdateState = .idle

    // A GUI app inherits almost no PATH, so brew has to be found by absolute path.
    // These are Homebrew's two standard prefixes: Apple silicon, then Intel.
    private static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// Upgrades the cask and relaunches into the new build.
    func updateAndRestart() async {
        guard state != .running else { return }
        state = .running

        guard let brew = Self.brewPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            state = .failed("Homebrew not found. Run manually: brew upgrade --cask portbar")
            return
        }

        // `update` first: without a refreshed tap, brew still sees the old version.
        let result = await Self.run("\(Self.quote(brew)) update && \(Self.quote(brew)) upgrade --cask portbar")
        guard result.status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            state = .failed(detail.isEmpty ? "brew exited with status \(result.status)" : detail)
            return
        }

        relaunch()
    }

    // The cask replaces the bundle in place, so the new build is at the same path.
    // The helper waits for this process to exit before reopening — launching while
    // the old instance is alive would just focus the old one.
    private func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \(Self.quote(path))"
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        do {
            try helper.run()
        } catch {
            state = .failed("Updated, but relaunch failed — reopen PortBar manually.")
            return
        }
        NSApp.terminate(nil)
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command, capturing merged output and the exit status. The shared
    /// `shell()` helper drops both, which an updater needs in order to report failure.
    private nonisolated static func run(_ command: String) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (
                    proc.terminationStatus,
                    String(data: data, encoding: .utf8) ?? ""
                ))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

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
