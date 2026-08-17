import SwiftUI

// One column of the popover table. The header and the row both iterate this list,
// so a column's width and alignment live in exactly one place — previously they
// were duplicated between `columnHeader` and `PortPopoverRow` and drifted easily.
enum PortColumn: String, CaseIterable, Identifiable, Codable {
    case health
    case port
    case process
    case type
    case project
    case cpu
    case memory
    case memoryPercent
    case pid
    case uptime
    case tools

    var id: String { rawValue }

    enum Width {
        case fixed(CGFloat)
        case flexible(min: CGFloat)
    }

    // Palette sections in the layout editor.
    enum Group: String, CaseIterable {
        case identity = "Identity"
        case resource = "Usage"
        case meta     = "Meta"
    }

    var title: String {
        switch self {
        case .health:  return "H"
        case .port:    return "PORT"
        case .process: return "PROCESS"
        case .type:    return "TYPE"
        case .project: return "PROJECT"
        case .cpu:     return "CPU"
        case .memory:  return "MEM"
        case .memoryPercent: return "%MEM"
        case .pid:     return "PID"
        case .uptime:  return "UPTIME"
        case .tools:   return "TOOLS"
        }
    }

    // Shown on the chips in the layout editor.
    var icon: String {
        switch self {
        case .health:  return "circle.fill"
        case .port:    return "number"
        case .process: return "terminal"
        case .type:    return "shippingbox"
        case .project: return "folder"
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .memoryPercent: return "chart.bar"
        case .pid:     return "number.square"
        case .uptime:  return "clock"
        case .tools:   return "wrench.and.screwdriver"
        }
    }

    var group: Group {
        switch self {
        case .health, .port, .process, .type, .project: return .identity
        case .cpu, .memory, .memoryPercent:             return .resource
        case .pid, .uptime, .tools:                     return .meta
        }
    }

    var width: Width {
        switch self {
        case .health:  return .fixed(20)    // dot
        case .port:    return .fixed(58)    // :3000
        case .process: return .flexible(min: 90)   // grows with the panel so full paths show
        case .type:    return .fixed(90)    // Next.js, Vite …
        case .project: return .fixed(120)
        case .cpu:     return .fixed(62)    // bar + "12.8%"
        case .memory:  return .fixed(72)    // bar + "1.2 GB"
        case .memoryPercent: return .fixed(58)
        case .pid:     return .fixed(56)
        case .uptime:  return .fixed(56)    // 2h 4m
        // 112 = 18 (LAN marker) + 30 (browser slot) + 26 + 26 (copy, kill) + 3*4
        // spacing. At the old 104 the buttons overflowed their own frame and spilled
        // left of the TOOLS header.
        case .tools:   return .fixed(112)
        }
    }

    // Gutter kept outside the frame so header and cell stay aligned.
    var trailingPadding: CGFloat { self == .uptime ? 10 : 0 }
    var leadingPadding: CGFloat { self == .port ? 8 : 0 }

    var headerAlignment: Alignment {
        switch self {
        case .health, .port, .tools: return .center
        case .uptime, .pid, .cpu, .memory, .memoryPercent: return .trailing
        default:                     return .leading
        }
    }

    var cellAlignment: Alignment {
        switch self {
        case .health:  return .center
        case .uptime, .pid: return .trailing
        case .cpu, .memory, .memoryPercent: return .trailing
        case .tools:   return .trailing
        default:       return .leading
        }
    }

    // Removing these leaves a row with no identity, or no way to kill the process.
    var isLocked: Bool { self == .port || self == .tools }

    // Space this column needs before rows start clipping.
    var minimumWidth: CGFloat {
        let base: CGFloat
        switch width {
        case .fixed(let w):       base = w
        case .flexible(let m):    base = m
        }
        return base + leadingPadding + trailingPadding
    }

    // The layout shipped before columns were configurable — unchanged so existing
    // installs see exactly what they saw yesterday.
    static let defaultLayout: [PortColumn] = [.health, .port, .process, .type, .project, .uptime, .tools]

    /// Reads a stored layout, repairing anything unusable rather than failing.
    /// Guards against a downgrade (raw values this build doesn't know), a corrupted
    /// write (duplicates), and hand-edited defaults that dropped a locked column.
    static func sanitized(_ rawValues: [String]?) -> [PortColumn] {
        guard let rawValues, !rawValues.isEmpty else { return defaultLayout }
        var seen = Set<PortColumn>()
        var result = rawValues.compactMap(PortColumn.init(rawValue:)).filter { seen.insert($0).inserted }
        guard !result.isEmpty else { return defaultLayout }
        for locked in defaultLayout where locked.isLocked && !result.contains(locked) {
            result.append(locked)
        }
        return result
    }
}

extension View {
    // Applies a column's width the same way for the header and the cell.
    @ViewBuilder
    func portColumnFrame(_ column: PortColumn, alignment: Alignment) -> some View {
        switch column.width {
        case .fixed(let w):
            self.frame(width: w, alignment: alignment)
                .padding(.leading, column.leadingPadding)
                .padding(.trailing, column.trailingPadding)
        case .flexible(let m):
            self.frame(minWidth: m, maxWidth: .infinity, alignment: alignment)
                .padding(.leading, column.leadingPadding)
                .padding(.trailing, column.trailingPadding)
        }
    }
}
