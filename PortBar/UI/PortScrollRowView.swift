import AppKit

/// Flipped view so subviews are laid out top-to-bottom
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A single port row inside the scrollable flat-list menu item.
/// Clicking it pops up a context menu with Kill / Open / Copy actions.
class PortScrollRowView: NSView {
    static let rowHeight: CGFloat = 26

    private let entry: PortEntry
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(entry: PortEntry, frame: NSRect) {
        self.entry = entry
        super.init(frame: frame)
        refreshTracking()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        refreshTracking()
    }

    private func refreshTracking() {
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        buildTitle().draw(in: bounds.insetBy(dx: 10, dy: 4))
    }

    private func buildTitle() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let dotColor: NSColor
        switch entry.health {
        case .healthy:  dotColor = .systemGreen
        case .orphaned: dotColor = .systemYellow
        case .zombie:   dotColor = .systemRed
        }
        result.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor]))

        result.append(NSAttributedString(
            string: ":\(entry.port)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)]
        ))

        let label = entry.framework != .unknown
            ? entry.framework.rawValue
            : (entry.projectName ?? entry.processName)
        result.append(NSAttributedString(string: "  \(label)"))

        if let project = entry.projectName, !project.isEmpty {
            result.append(NSAttributedString(string: "  \(project)",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        }

        result.append(NSAttributedString(string: "  \(formatUptime(entry.uptime))",
            attributes: [.foregroundColor: NSColor.tertiaryLabelColor]))

        return result
    }

    // MARK: - Context menu

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let killItem = NSMenuItem(title: "Kill Process (PID \(entry.pid))",
            action: #selector(KillTarget.kill(_:)), keyEquivalent: "")
        killItem.representedObject = entry as AnyObject
        killItem.target = KillTarget.shared
        menu.addItem(killItem)

        if isHTTPPort(entry.port) {
            let openItem = NSMenuItem(title: "Open in Browser",
                action: #selector(OpenBrowserTarget.open(_:)), keyEquivalent: "")
            openItem.representedObject = entry as AnyObject
            openItem.target = OpenBrowserTarget.shared
            menu.addItem(openItem)
        }

        let copyItem = NSMenuItem(title: "Copy :\(entry.port)",
            action: #selector(CopyTarget.copy(_:)), keyEquivalent: "")
        copyItem.representedObject = entry as AnyObject
        copyItem.target = CopyTarget.shared
        menu.addItem(copyItem)

        menu.addItem(.separator())

        if let path = entry.projectPath {
            let pathItem = NSMenuItem(title: path,
                action: #selector(RevealTarget.reveal(_:)), keyEquivalent: "")
            pathItem.representedObject = entry as AnyObject
            pathItem.target = RevealTarget.shared
            menu.addItem(pathItem)
        }

        let label = entry.framework != .unknown ? entry.framework.rawValue : entry.processName
        let infoItem = NSMenuItem(
            title: "\(label) · \(formatUptime(entry.uptime)) · PID \(entry.pid)",
            action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        return menu
    }

    private func isHTTPPort(_ port: Int) -> Bool {
        port == 80 || port == 443
            || (3000...3999).contains(port)
            || (4000...4999).contains(port)
            || (8000...8999).contains(port)
    }
}
