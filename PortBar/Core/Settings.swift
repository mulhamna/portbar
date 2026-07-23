import Foundation
import Combine
import CoreGraphics

final class PortBarSettings: ObservableObject {
    static let shared = PortBarSettings()
    private init() {}

    // Popover size — user-resizable via the footer grip, persisted across launches.
    // Lower bound must fit every column or rows overflow and get clipped.
    static let widthRange: ClosedRange<CGFloat>  = 600...1100
    static let heightRange: ClosedRange<CGFloat> = 240...760

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
