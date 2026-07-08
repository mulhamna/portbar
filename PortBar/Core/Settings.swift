import Foundation
import Combine
import CoreGraphics

final class PortBarSettings: ObservableObject {
    static let shared = PortBarSettings()
    private init() {}

    // Popover size — user-resizable via the footer grip, persisted across launches.
    static let widthRange: ClosedRange<CGFloat>  = 460...1000
    static let heightRange: ClosedRange<CGFloat> = 240...760

    @Published var popoverWidth: CGFloat = {
        let v = CGFloat(UserDefaults.standard.double(forKey: "pb.popoverWidth"))
        return v > 0 ? v : 520
    }() {
        didSet { UserDefaults.standard.set(Double(popoverWidth), forKey: "pb.popoverWidth") }
    }

    @Published var popoverListHeight: CGFloat = {
        let v = CGFloat(UserDefaults.standard.double(forKey: "pb.popoverListHeight"))
        return v > 0 ? v : 400
    }() {
        didSet { UserDefaults.standard.set(Double(popoverListHeight), forKey: "pb.popoverListHeight") }
    }

    enum DisplayMode: String, CaseIterable {
        case grouped = "grouped"
        case flat    = "flat"

        var label: String {
            switch self {
            case .grouped: return "Grouped by Category"
            case .flat:    return "Flat List (Scrollable)"
            }
        }
    }

    @Published var displayMode: DisplayMode = {
        let raw = UserDefaults.standard.string(forKey: "pb.displayMode") ?? ""
        return DisplayMode(rawValue: raw) ?? .grouped
    }() {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "pb.displayMode") }
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
}
