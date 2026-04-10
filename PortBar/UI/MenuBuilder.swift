import AppKit

// Wraps a () -> Void so it can be stored in NSMenuItem.representedObject (Any?)
private class CallbackHolder: NSObject {
    let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
}

struct MenuBuilder {
    @MainActor
    static func build(
        from ports: [PortEntry],
        watchService: WatchService,
        onRefresh: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        // Watch toggle
        let watchTitle = watchService.isWatching ? "◉ Watch Mode" : "Watch Mode"
        let watchItem = NSMenuItem(title: watchTitle, action: #selector(WatchToggleTarget.toggle(_:)), keyEquivalent: "")
        watchItem.state = watchService.isWatching ? .on : .off
        watchItem.representedObject = watchService
        watchItem.target = WatchToggleTarget.shared
        menu.addItem(watchItem)

        // Refresh
        let refreshItem = NSMenuItem(title: "↻ Refresh", action: #selector(RefreshTarget.refresh(_:)), keyEquivalent: "r")
        refreshItem.representedObject = CallbackHolder(onRefresh)
        refreshItem.target = RefreshTarget.shared
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        if ports.isEmpty {
            menu.addItem(NSMenuItem(title: "No active ports", action: nil, keyEquivalent: ""))
        } else {
            for entry in ports {
                menu.addItem(makePortItem(entry: entry))
            }
        }

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About PortBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Port row

    private static func makePortItem(entry: PortEntry) -> NSMenuItem {
        let uptime = formatUptime(entry.uptime)
        let project = entry.projectName ?? ""
        let health = healthLabel(entry.health)
        let title = ":\(entry.port)  \(entry.framework.rawValue)  \(project)  \(uptime)  \(health)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = makeSubmenu(entry: entry)
        return item
    }

    private static func makeSubmenu(entry: PortEntry) -> NSMenu {
        let sub = NSMenu()

        let killItem = NSMenuItem(title: "Kill Process (PID \(entry.pid))", action: #selector(KillTarget.kill(_:)), keyEquivalent: "")
        killItem.representedObject = entry as AnyObject
        killItem.target = KillTarget.shared
        sub.addItem(killItem)

        if isHTTPPort(entry.port) {
            let openItem = NSMenuItem(title: "Open in Browser", action: #selector(OpenBrowserTarget.open(_:)), keyEquivalent: "")
            openItem.representedObject = entry as AnyObject
            openItem.target = OpenBrowserTarget.shared
            sub.addItem(openItem)
        }

        let copyItem = NSMenuItem(title: "Copy :\(entry.port)", action: #selector(CopyTarget.copy(_:)), keyEquivalent: "")
        copyItem.representedObject = entry as AnyObject
        copyItem.target = CopyTarget.shared
        sub.addItem(copyItem)

        sub.addItem(.separator())

        if let path = entry.projectPath {
            let pathItem = NSMenuItem(title: path, action: #selector(RevealTarget.reveal(_:)), keyEquivalent: "")
            pathItem.representedObject = entry as AnyObject
            pathItem.target = RevealTarget.shared
            sub.addItem(pathItem)
        }

        let infoItem = NSMenuItem(
            title: "\(entry.framework.rawValue) · \(formatUptime(entry.uptime)) · PID \(entry.pid)",
            action: nil, keyEquivalent: ""
        )
        infoItem.isEnabled = false
        sub.addItem(infoItem)

        return sub
    }

    private static func healthLabel(_ health: HealthStatus) -> String {
        switch health {
        case .healthy: return "● healthy"
        case .orphaned: return "◐ orphaned"
        case .zombie: return "○ zombie"
        }
    }

    private static func isHTTPPort(_ port: Int) -> Bool {
        port == 80 || port == 443
            || (3000...3999).contains(port)
            || (4000...4999).contains(port)
            || (8000...8999).contains(port)
    }
}

// MARK: - Action targets

class WatchToggleTarget: NSObject {
    static let shared = WatchToggleTarget()
    @objc func toggle(_ sender: NSMenuItem) {
        guard let ws = sender.representedObject as? WatchService else { return }
        Task { @MainActor in
            if ws.isWatching { ws.stopWatching() } else { ws.startWatching() }
        }
    }
}

class RefreshTarget: NSObject {
    static let shared = RefreshTarget()
    @objc func refresh(_ sender: NSMenuItem) {
        guard let holder = sender.representedObject as? CallbackHolder else { return }
        holder.callback()
    }
}

class KillTarget: NSObject {
    static let shared = KillTarget()
    @objc func kill(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PortEntry else { return }
        Task { await ProcessKiller.kill(entry: entry) }
    }
}

class OpenBrowserTarget: NSObject {
    static let shared = OpenBrowserTarget()
    @objc func open(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PortEntry,
              let url = URL(string: "http://localhost:\(entry.port)") else { return }
        NSWorkspace.shared.open(url)
    }
}

class CopyTarget: NSObject {
    static let shared = CopyTarget()
    @objc func copy(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PortEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(":\(entry.port)", forType: .string)
    }
}

class RevealTarget: NSObject {
    static let shared = RevealTarget()
    @objc func reveal(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PortEntry,
              let path = entry.projectPath else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
