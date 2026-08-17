import SwiftUI
import AppKit
import UserNotifications

// Column widths and alignment live in PortColumn — the header and the row both
// iterate settings.columns so they can't drift apart.

// MARK: - Root

struct PortListPopoverView: View {
    @ObservedObject var watchService: WatchService
    @ObservedObject private var settings = PortBarSettings.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var searchText = ""
    @State private var dragBaseWidth: CGFloat?
    @State private var dragBaseHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            portList
            Divider()
            footer
        }
        .frame(width: min(settings.popoverWidth, settings.maxPopoverWidth))
        .background(Color(NSColor.windowBackgroundColor))
    }


    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("PortBar")
                .font(.headline)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .frame(maxWidth: 150)

            Spacer()

            Button {
                watchService.showAll.toggle()
            } label: {
                Label("All", systemImage: watchService.showAll ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(watchService.showAll ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                if watchService.isWatching { watchService.stopWatching() }
                else { watchService.startWatching() }
            } label: {
                Label(
                    watchService.isWatching ? "Watching" : "Watch",
                    systemImage: watchService.isWatching ? "eye.fill" : "eye"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(watchService.isWatching ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button { Task { await watchService.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                SettingsWindowController.shared.show(watchService: watchService)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.secondary)
                    if updater.hasUpdate {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .task { await updater.check() }

            Text("⚡ " + String(filteredPorts.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Settings panel


    // MARK: Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            // Matches the row's group-color stripe so the columns line up.
            Color.clear.frame(width: 3, height: 1)

            ForEach(settings.columns) { column in
                Text(column.title)
                    .portColumnFrame(column, alignment: column.headerAlignment)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .padding(.leading, 14)
        .padding(.trailing, 26)   // match row gutter so columns stay aligned
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Filtering & grouping

    private var filteredPorts: [PortEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return watchService.ports }
        let qLower = q.lowercased()
        return watchService.ports.filter { entry in
            String(entry.port).contains(q)
                || entry.processName.lowercased().contains(qLower)
                || (entry.projectName?.lowercased().contains(qLower) ?? false)
        }
    }

    // Same-cwd grouping only — Docker containers carry no projectPath today.
    private var relatedGroups: [String: [PortEntry]] {
        Dictionary(grouping: watchService.ports.filter { $0.projectPath != nil }) { $0.projectPath! }
            .filter { $0.value.count > 1 }
    }

    private static let groupPalette: [Color] = [.blue, .purple, .orange, .teal, .pink, .mint, .indigo, .yellow]

    // Cluster related ports next to each other instead of pure ascending order.
    private var orderedPorts: [PortEntry] {
        func clusterKey(_ entry: PortEntry) -> Int {
            if let path = entry.projectPath, let group = relatedGroups[path] {
                return group.map(\.port).min() ?? entry.port
            }
            return entry.port
        }
        return filteredPorts.sorted { a, b in
            let ka = clusterKey(a), kb = clusterKey(b)
            if ka != kb { return ka < kb }
            return a.port < b.port
        }
    }

    private func groupColor(for entry: PortEntry) -> Color? {
        guard let path = entry.projectPath, relatedGroups[path] != nil else { return nil }
        let sortedPaths = relatedGroups.keys.sorted()
        guard let index = sortedPaths.firstIndex(of: path) else { return nil }
        return Self.groupPalette[index % Self.groupPalette.count]
    }

    // MARK: Port list

    private var portList: some View {
        Group {
            if watchService.ports.isEmpty {
                Text("No active ports")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else if filteredPorts.isEmpty {
                Text("No ports match \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else {
                ScrollView {
                    // The header is pinned *inside* the scroll view on purpose. Laid
                    // out beside it, the header and the rows sat in two different
                    // layout contexts: the scroller's gutter narrowed the rows but not
                    // the header, the flexible PROCESS column absorbed the difference,
                    // and every column after it drifted out of line.
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(orderedPorts) { entry in
                                PortPopoverRow(entry: entry, groupColor: groupColor(for: entry), watchService: watchService)
                                Divider().padding(.leading, 14)
                            }
                        } header: {
                            columnHeader
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: orderedPorts.map { $0.id })
                }
                .frame(maxHeight: settings.popoverListHeight)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(String(filteredPorts.count) + " ports listening")
                .font(.caption)
                .foregroundStyle(Color.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.secondary)

            resizeGrip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // Drag to resize the panel (width + list height), persisted in settings.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.leading, 8)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture()
                    .onChanged { g in
                        let baseW = dragBaseWidth ?? settings.popoverWidth
                        let baseH = dragBaseHeight ?? settings.popoverListHeight
                        dragBaseWidth = baseW
                        dragBaseHeight = baseH
                        settings.popoverWidth = (baseW + g.translation.width)
                            .clamped(to: settings.effectiveWidthRange)
                        settings.popoverListHeight = (baseH + g.translation.height)
                            .clamped(to: PortBarSettings.heightRange)
                    }
                    .onEnded { _ in
                        dragBaseWidth = nil
                        dragBaseHeight = nil
                    }
            )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Row

struct PortPopoverRow: View {
    let entry: PortEntry
    let groupColor: Color?
    @ObservedObject var watchService: WatchService
    @ObservedObject private var settings = PortBarSettings.shared
    @State private var hovered = false
    @State private var hoverProcess = false
    @State private var hoverProject = false

    var body: some View {
        HStack(spacing: 0) {

            // Related-project color stripe — same color = same project group.
            Rectangle()
                .fill(groupColor ?? .clear)
                .frame(width: 3)

            ForEach(settings.columns) { column in
                cell(for: column)
                    .portColumnFrame(column, alignment: column.cellAlignment)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 26)   // clear the scroll bar gutter so ✕ isn't covered
        .padding(.vertical, 6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.1) : Color.clear)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
    }

    // MARK: Cells

    @ViewBuilder
    private func cell(for column: PortColumn) -> some View {
        switch column {
        case .health:
            Circle()
                .fill(healthColor)
                .frame(width: 7, height: 7)

        case .port:
            Text(":" + String(entry.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))

        case .process:
            // Full path; column grows with the panel width. Hover = tooltip.
            Text(entry.processName)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .onHover { hoverProcess = $0 }
                .overlay(alignment: .topLeading) {
                    if hoverProcess { HoverPathBubble(text: entry.processName) }
                }

        case .type:
            Text(label)
                .lineLimit(1)

        case .project:
            Text(entry.projectName ?? "—")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .onHover { hoverProject = $0 }
                .overlay(alignment: .topLeading) {
                    if hoverProject, let p = entry.projectPath ?? entry.projectName {
                        HoverPathBubble(text: p)
                    }
                }

        case .cpu:
            // ps reports a decaying average over roughly the last minute, and a
            // multi-threaded process can exceed 100 — clamp so the bar stays sane.
            MetricBar(
                fraction: entry.cpuPercent.map { min($0, 100) / 100 },
                text: entry.cpuPercent.map { String(format: "%.1f%%", $0) },
                tint: loadTint(entry.cpuPercent, warn: 50, alarm: 85)
            )
            .help("CPU — average over roughly the last minute")

        case .memory:
            // Bar tracks %MEM because RSS on its own has no sensible ceiling.
            MetricBar(
                fraction: entry.memoryPercent.map { min($0, 100) / 100 },
                text: entry.memoryRSS.map(formatMemory),
                tint: loadTint(entry.memoryPercent, warn: 5, alarm: 15)
            )

        case .memoryPercent:
            MetricBar(
                fraction: entry.memoryPercent.map { min($0, 100) / 100 },
                text: entry.memoryPercent.map { String(format: "%.1f%%", $0) },
                tint: loadTint(entry.memoryPercent, warn: 5, alarm: 15)
            )

        case .pid:
            Text(String(entry.pid))
                .foregroundStyle(.tertiary)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)

        case .uptime:
            Text(formatUptime(entry.uptime))
                .foregroundStyle(.tertiary)
                .font(.caption.monospacedDigit())

        case .tools:
            HStack(spacing: 4) {
                // LAN-exposure marker: other devices can reach this port.
                if entry.bindScope == .exposed {
                    Image(systemName: "dot.radiowaves.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 18)
                        .help("Reachable from other devices on your network")
                } else {
                    Spacer().frame(width: 18)   // keep actions aligned
                }
                if shouldOfferBrowser(entry) {
                    PortActionButton(icon: "globe", tint: .blue) { openBrowser() }
                } else {
                    Spacer().frame(width: 30)   // keep kill/copy aligned
                }
                PortActionButton(icon: "doc.on.doc", tint: Color(NSColor.secondaryLabelColor)) { copyPort() }
                PortActionButton(icon: "xmark.circle.fill", tint: .red) {
                    Task { await ProcessKiller.kill(entry: entry, watchService: watchService) }
                }
            }
        }
    }

    // MARK: Helpers

    private var label: String {
        entry.framework != .unknown ? entry.framework.rawValue : (entry.projectName ?? entry.processName)
    }

    private var healthColor: Color {
        switch entry.health {
        case .healthy:  return .green
        case .orphaned: return .yellow
        case .zombie:   return .red
        }
    }

    private func openBrowser() {
        guard let url = localhostURL(port: entry.port) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyPort() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(":" + String(entry.port), forType: .string)
    }

    private func loadTint(_ value: Double?, warn: Double, alarm: Double) -> Color {
        guard let value else { return .secondary }
        if value >= alarm { return .red }
        if value >= warn  { return .orange }
        return .green
    }
}

// MARK: - Metric bar

// A number with its own scale behind it, so a busy port is visible while scanning
// the list instead of requiring the reader to compare digits.
struct MetricBar: View {
    let fraction: Double?   // 0…1, nil when the metric doesn't apply (Docker rows)
    let text: String?
    let tint: Color

    var body: some View {
        ZStack(alignment: .trailing) {
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(tint.opacity(0.30))
                            // A live-but-idle process should still show a sliver.
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
            }
            Text(text ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(text == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .frame(height: 15)
        // GeometryReader has no intrinsic width, so without this the ZStack collapses
        // to the width of its Text and the bar renders narrower than its column —
        // making each row's bar a different length and pulling the number off the
        // header above it.
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hover reveal bubble (SwiftUI .help / native toolTip are unreliable in NSPopover)

struct HoverPathBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 460, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            .offset(y: 22)
            .zIndex(100)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

// MARK: - Action button

struct PortActionButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 22)
                .background(hovered ? tint.opacity(0.2) : tint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}
