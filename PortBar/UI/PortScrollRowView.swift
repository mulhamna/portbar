import AppKit

// MARK: - Layout helpers

/// Flipped NSView so subviews stack top-to-bottom (y=0 at top).
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// NSScrollView that captures scroll wheel events so NSMenu's private
/// tracking loop doesn't steal them.
class MenuEmbeddedScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let docHeight  = documentView?.frame.height ?? 0
        let clipHeight = contentView.bounds.height
        let originY    = contentView.bounds.origin.y

        let atTop    = originY <= 0
        let atBottom = originY >= docHeight - clipHeight
        let goingUp  = event.scrollingDeltaY > 0
        let goingDown = event.scrollingDeltaY < 0

        if (goingUp && atTop) || (goingDown && atBottom) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Per-row action target

/// Holds a strong reference to the entry so the @objc action fires correctly.
private class RowTarget: NSObject {
    let entry: PortEntry
    init(_ entry: PortEntry) { self.entry = entry }

    @objc func clicked(_ sender: NSButton) {
        // Build the same submenu as grouped mode (Kill / Open / Copy / Reveal)
        let menu = MenuBuilder.makePortSubmenu(entry: entry)
        // popUp(positioning:at:in:) works inside an NSMenu session —
        // it opens a new tracking session, dismissing the parent menu first.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height),
                   in: sender)
    }
}

// MARK: - Row view

class PortScrollRowView: NSView {
    static let rowHeight: CGFloat = 26

    // Strong ref — NSButton only holds a weak ref to target
    private let rowTarget: RowTarget

    init(entry: PortEntry, frame: NSRect) {
        self.rowTarget = RowTarget(entry)
        super.init(frame: frame)

        let btn = NSButton(frame: bounds)
        btn.bezelStyle       = .regularSquare
        btn.isBordered       = false
        btn.imagePosition    = .noImage
        btn.alignment        = .left
        btn.autoresizingMask = [.width, .height]
        btn.target           = rowTarget
        btn.action           = #selector(RowTarget.clicked(_:))
        btn.attributedTitle  = MenuBuilder.buildPortTitle(entry: entry)
        addSubview(btn)
    }

    required init?(coder: NSCoder) { fatalError() }
}
