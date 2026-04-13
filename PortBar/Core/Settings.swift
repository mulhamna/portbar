import Foundation
import Combine

final class PortBarSettings: ObservableObject {
    static let shared = PortBarSettings()
    private init() {}

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

    @Published var autoWatch: Bool = UserDefaults.standard.bool(forKey: "pb.autoWatch") {
        didSet { UserDefaults.standard.set(autoWatch, forKey: "pb.autoWatch") }
    }

    @Published var defaultShowAll: Bool = UserDefaults.standard.bool(forKey: "pb.defaultShowAll") {
        didSet { UserDefaults.standard.set(defaultShowAll, forKey: "pb.defaultShowAll") }
    }
}
