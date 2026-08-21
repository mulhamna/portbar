import Foundation
import Combine
import CoreGraphics

final class PortBarSettings: ObservableObject {
    static let shared = PortBarSettings()
    private init() {}

    // Popover size — user-resizable via the footer grip, persisted across launches.
    // The lower bound is derived from the enabled columns (see minPopoverWidth), so
    // a narrow layout can shrink further than the old fixed 600 and a wide one can't
    // be dragged small enough to clip rows.
    static let widthRange: ClosedRange<CGFloat>  = 360...1100
    static let heightRange: ClosedRange<CGFloat> = 240...760

    // Row chrome outside the columns: 14pt leading + 26pt scrollbar gutter + 3pt
    // group stripe, rounded up so the default layout lands on the historical 600.
    private static let rowChrome: CGFloat = 44

    /// Narrowest width that still renders every enabled column without clipping.
    var minPopoverWidth: CGFloat {
        let content = columns.reduce(CGFloat(0)) { $0 + $1.minimumWidth }
        return min(max(content + Self.rowChrome, Self.widthRange.lowerBound), Self.widthRange.upperBound)
    }

    /// Resize bounds for the current column set.
    var effectiveWidthRange: ClosedRange<CGFloat> { minPopoverWidth...Self.widthRange.upperBound }

    /// Width actually rendered: the user's preference, never narrower than the columns
    /// need, never wider than the screen allows. The screen cap yields to the column
    /// minimum — a clipped row is worse than a panel that reaches a little further.
    /// Both the popover view and StatusBarController read this, so the frame AppKit
    /// positions and the frame SwiftUI draws can't disagree.
    var renderWidth: CGFloat {
        let floor = minPopoverWidth
        return min(max(popoverWidth, floor), max(maxPopoverWidth, floor))
    }

    // Order and membership of the popover's columns.
    @Published var columns: [PortColumn] = PortColumn.sanitized(
        UserDefaults.standard.stringArray(forKey: "pb.columns")
    ) {
        didSet {
            UserDefaults.standard.set(columns.map(\.rawValue), forKey: "pb.columns")
            // Adding a column to an already-narrow panel would otherwise clip rows.
            let range = effectiveWidthRange
            popoverWidth = min(max(popoverWidth, range.lowerBound), range.upperBound)
        }
    }

    @Published var popoverWidth: CGFloat = {
        let v = CGFloat(UserDefaults.standard.double(forKey: "pb.popoverWidth"))
        let d = v > 0 ? v : 600
        return min(max(d, widthRange.lowerBound), widthRange.upperBound)
    }() {
        didSet { UserDefaults.standard.set(Double(popoverWidth), forKey: "pb.popoverWidth") }
    }

    // Runtime-only (not persisted). Set by StatusBarController from the icon's screen
    // position each time the popover opens, so a center-anchored popover never falls
    // off-screen near the menu bar edge.
    @Published var maxPopoverWidth: CGFloat = .greatestFiniteMagnitude

    // Same deal for height: the settings panel is tall enough to push the toolbar off
    // the top of the display, so it needs to know what the screen actually allows.
    @Published var maxPopoverHeight: CGFloat = 720

    @Published var popoverListHeight: CGFloat = {
        let v = CGFloat(UserDefaults.standard.double(forKey: "pb.popoverListHeight"))
        let d = v > 0 ? v : 400
        return min(max(d, heightRange.lowerBound), heightRange.upperBound)
    }() {
        didSet { UserDefaults.standard.set(Double(popoverListHeight), forKey: "pb.popoverListHeight") }
    }

    @Published var autoWatch: Bool = {
        let key = "pb.autoWatch"
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(autoWatch, forKey: "pb.autoWatch") }
    }

    @Published var defaultShowAll: Bool = UserDefaults.standard.bool(forKey: "pb.defaultShowAll") {
        didSet { UserDefaults.standard.set(defaultShowAll, forKey: "pb.defaultShowAll") }
    }

    // Menu bar shows just ⚡ by default; opt in to the numeric count.
    @Published var showCount: Bool = UserDefaults.standard.bool(forKey: "pb.showCount") {
        didSet { UserDefaults.standard.set(showCount, forKey: "pb.showCount") }
    }

    // Opt-in: avoids an unprompted notification permission dialog on first launch.
    @Published var notifyOnNewPort: Bool = UserDefaults.standard.bool(forKey: "pb.notifyOnNewPort") {
        didSet { UserDefaults.standard.set(notifyOnNewPort, forKey: "pb.notifyOnNewPort") }
    }
}
