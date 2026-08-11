import AppKit
import Darwin

struct ProcessKiller {
    static func kill(entry: PortEntry, watchService: WatchService) async {
        let confirmed = await MainActor.run { () -> Bool in
            var siblingCount = 0
            if let path = entry.projectPath {
                let siblings = watchService.ports.filter { $0.projectPath == path && $0.pid != entry.pid }
                siblingCount = siblings.count
            }

            let alert = NSAlert()
            alert.messageText = "Kill \(entry.processName) on :\(entry.port)?"
            let baseInfo: String
            if let project = entry.projectName {
                baseInfo = "Project: \(project)"
            } else {
                baseInfo = "PID: \(entry.pid)"
            }
            if siblingCount > 0 {
                alert.informativeText = baseInfo + "\n\(siblingCount) other port(s) share this project and may be affected."
            } else {
                alert.informativeText = baseInfo
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Kill")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }

        guard confirmed else { return }

        let pid = pid_t(entry.pid)
        // ponytail: kill the whole process group so dev-server child workers die
        // too and can't hold the port or respawn. Fall back to single-pid if the
        // process shares our own group (never nuke PortBar's terminal/session).
        let pgid = getpgid(pid)
        let useGroup = pgid > 0 && pgid != getpgid(0)
        let target: pid_t = useGroup ? -pgid : pid

        Darwin.kill(target, SIGTERM)

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(target, SIGKILL)
        }

        // #1: reflect the kill immediately instead of waiting for the next poll.
        await watchService.refresh()
    }
}
