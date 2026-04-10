import AppKit

// Wraps a () -> Void so it can be stored in NSMenuItem.representedObject (Any?)
private class CallbackHolder: NSObject {
    let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
}

// How many ports to show inline per category before collapsing the rest
private let kInlineLimit = 6

// MARK: - Category

private enum PortCategory: String, CaseIterable {
    case dev      = "DEV SERVERS"
    case database = "DATABASES"
    case docker   = "DOCKER"
    case other    = "OTHER"
}

private func category(for entry: PortEntry) -> PortCategory {
    switch entry.framework {
    case .nextjs, .vite, .express, .remix, .astro, .angular, .nuxt,
         .node, .django, .fastapi, .flask, .rails, .python, .ruby:
        return .dev
    case .postgresql, .redis, .mongodb, .mysql:
        return .database
    case .docker, .nginx, .localstack:
        return .docker
    case .unknown:
        return .other
    }
}

// MARK: - Builder

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
            switch PortBarSettings.shared.displayMode {
            case .grouped: addPortSections(ports: ports, to: menu)
            case .flat:    addFlatList(ports: ports, to: menu)
            }
        }

        menu.addItem(.separator())

        menu.addItem(makeSettingsItem())

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About PortBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Settings submenu

    private static func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let header = NSMenuItem(title: "DISPLAY MODE", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "DISPLAY MODE",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            ]
        )
        sub.addItem(header)

        let current = PortBarSettings.shared.displayMode
        for mode in PortBarSettings.DisplayMode.allCases {
            let modeItem = NSMenuItem(title: mode.label, action: #selector(DisplayModeTarget.setMode(_:)), keyEquivalent: "")
            modeItem.representedObject = mode.rawValue as AnyObject
            modeItem.target = DisplayModeTarget.shared
            modeItem.state = (mode == current) ? .on : .off
            sub.addItem(modeItem)
        }

        item.submenu = sub
        return item
    }

    // MARK: - Flat list

    private static func addFlatList(ports: [PortEntry], to menu: NSMenu) {
        for entry in ports {
            menu.addItem(makePortItem(entry: entry))
        }
    }

    // MARK: - Grouped sections

    private static func addPortSections(ports: [PortEntry], to menu: NSMenu) {
        // Group ports by category, preserving sort order within each group
        var grouped: [PortCategory: [PortEntry]] = [:]
        for entry in ports {
            let cat = category(for: entry)
            grouped[cat, default: []].append(entry)
        }

        var didAddSection = false
        for cat in PortCategory.allCases {
            guard let entries = grouped[cat], !entries.isEmpty else { continue }

            if didAddSection { menu.addItem(.separator()) }
            didAddSection = true

            // Section header (greyed out, not selectable)
            let header = NSMenuItem(title: cat.rawValue, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(
                string: cat.rawValue,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                ]
            )
            menu.addItem(header)

            let inline = Array(entries.prefix(kInlineLimit))
            let overflow = Array(entries.dropFirst(kInlineLimit))

            for entry in inline {
                menu.addItem(makePortItem(entry: entry))
            }

            if !overflow.isEmpty {
                let moreItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                moreItem.attributedTitle = NSAttributedString(
                    string: "▸ \(overflow.count) more...",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
                let sub = NSMenu()
                for entry in overflow {
                    sub.addItem(makePortItem(entry: entry))
                }
                moreItem.submenu = sub
                menu.addItem(moreItem)
            }
        }
    }

    // MARK: - Port row

    private static func makePortItem(entry: PortEntry) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = buildPortTitle(entry: entry)
        item.submenu = makeSubmenu(entry: entry)
        return item
    }

    private static func buildPortTitle(entry: PortEntry) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Colored health dot
        let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: healthNSColor(entry.health)])
        result.append(dot)

        // Port (monospaced bold)
        let portStr = NSAttributedString(
            string: ":\(entry.port)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)]
        )
        result.append(portStr)

        // Framework or fallback label
        let label = frameworkLabel(entry)
        result.append(NSAttributedString(string: "  \(label)"))

        // Project name
        if let project = entry.projectName, !project.isEmpty {
            result.append(NSAttributedString(string: "  \(project)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        }

        // Uptime
        let uptime = formatUptime(entry.uptime)
        result.append(NSAttributedString(string: "  \(uptime)", attributes: [.foregroundColor: NSColor.tertiaryLabelColor]))

        return result
    }

    private static func frameworkLabel(_ entry: PortEntry) -> String {
        entry.framework != .unknown ? entry.framework.rawValue : (entry.projectName ?? entry.processName)
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
            title: "\(frameworkLabel(entry)) · \(formatUptime(entry.uptime)) · PID \(entry.pid)",
            action: nil, keyEquivalent: ""
        )
        infoItem.isEnabled = false
        sub.addItem(infoItem)

        return sub
    }

    // MARK: - Helpers

    private static func healthNSColor(_ health: HealthStatus) -> NSColor {
        switch health {
        case .healthy:  return .systemGreen
        case .orphaned: return .systemYellow
        case .zombie:   return .systemRed
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

class DisplayModeTarget: NSObject {
    static let shared = DisplayModeTarget()
    @objc func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PortBarSettings.DisplayMode(rawValue: raw) else { return }
        PortBarSettings.shared.displayMode = mode
    }
}

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
