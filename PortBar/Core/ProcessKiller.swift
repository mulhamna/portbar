import AppKit
import Darwin

struct ProcessKiller {
    static func kill(entry: PortEntry) async {
        let confirmed = await MainActor.run { () -> Bool in
            let alert = NSAlert()
            alert.messageText = "Kill \(entry.processName) on :\(entry.port)?"
            alert.informativeText = entry.projectName.map { "Project: \($0)" } ?? "PID: \(entry.pid)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Kill")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }

        guard confirmed else { return }

        let pid = pid_t(entry.pid)
        Darwin.kill(pid, SIGTERM)

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }
    }
}
