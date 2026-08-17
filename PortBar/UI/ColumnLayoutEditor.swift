import SwiftUI

// Drag-to-arrange editor for the popover's columns.
//
// Drag payload is the column's raw value as a plain String rather than a custom
// Transferable: String is already Transferable, so this needs no exported UTType
// and no Info.plist declaration. Every drop is validated through
// PortColumn(rawValue:), so unrelated text dragged in is simply refused.
struct ColumnLayoutEditor: View {
    @ObservedObject private var settings = PortBarSettings.shared
    @ObservedObject var watchService: WatchService

    @State private var dropTarget: PortColumn?
    @State private var trashTargeted = false

    private var available: [PortColumn] {
        PortColumn.allCases.filter { !settings.columns.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("LAYOUT", trailing: {
                Button("Reset") { settings.columns = PortColumn.defaultLayout }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .disabled(settings.columns == PortColumn.defaultLayout)
            })

            livePreview
            rowLayoutStrip
            trashStrip

            if !available.isEmpty {
                ForEach(PortColumn.Group.allCases, id: \.self) { group in
                    let items = available.filter { $0.group == group }
                    if !items.isEmpty {
                        Text(group.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(items) { column in
                                Button { append(column) } label: {
                                    ColumnChip(column: column, placed: false)
                                }
                                .buttonStyle(.plain)
                                .draggable(column.rawValue) {
                                    ColumnChip(column: column, placed: false)
                                }
                            }
                        }
                    }
                }
            }

            Text("Drag chips to reorder. Click one to add it, or drag it to the bin to remove. PORT and TOOLS stay put.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Sections

    // Renders the real row rather than a mock, so the preview can't drift from the
    // table. Hit testing is off: the sample entry has no real pid behind its buttons.
    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live preview")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            PortPopoverRow(entry: Self.sampleEntry, groupColor: .blue, watchService: watchService)
                .allowsHitTesting(false)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10)))
        }
    }

    private var rowLayoutStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(settings.columns) { column in
                    ColumnChip(column: column, placed: true)
                        .overlay(alignment: .leading) {
                            // Insertion caret for the slot this chip would be pushed out of.
                            if dropTarget == column {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: 2)
                                    .offset(x: -4)
                            }
                        }
                        .draggable(column.rawValue) { ColumnChip(column: column, placed: true) }
                        .dropDestination(for: String.self) { items, _ in
                            dropTarget = nil
                            return move(items.first, before: column)
                        } isTargeted: { targeted in
                            dropTarget = targeted ? column : (dropTarget == column ? nil : dropTarget)
                        }
                }

                // Trailing catch-all so a chip can be dropped at the end of the row.
                Color.clear
                    .frame(width: 40, height: 24)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        move(items.first, before: nil)
                    }
            }
            .padding(6)
        }
        .frame(height: 40)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var trashStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: "trash")
            Text("Drag here to remove")
        }
        .font(.caption2)
        .foregroundStyle(trashTargeted ? Color.red : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(trashTargeted ? Color.red.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(trashTargeted ? Color.red : Color.secondary.opacity(0.4))
        )
        .dropDestination(for: String.self) { items, _ in
            trashTargeted = false
            return remove(items.first)
        } isTargeted: { trashTargeted = $0 }
    }

    private func sectionTitle<T: View>(_ text: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Spacer()
            trailing()
        }
    }

    // MARK: Mutations

    /// Moves an existing column, or inserts a new one, ahead of `target`.
    /// `target == nil` appends. Returns false when the payload isn't a column.
    @discardableResult
    private func move(_ rawValue: String?, before target: PortColumn?) -> Bool {
        guard let rawValue, let column = PortColumn(rawValue: rawValue) else { return false }
        guard column != target else { return false }
        var columns = settings.columns
        columns.removeAll { $0 == column }
        if let target, let index = columns.firstIndex(of: target) {
            columns.insert(column, at: index)
        } else {
            columns.append(column)
        }
        settings.columns = columns
        return true
    }

    private func append(_ column: PortColumn) {
        move(column.rawValue, before: nil)
    }

    private func remove(_ rawValue: String?) -> Bool {
        guard let rawValue, let column = PortColumn(rawValue: rawValue), !column.isLocked else { return false }
        settings.columns.removeAll { $0 == column }
        return true
    }

    // Numbers picked to exercise every renderer: a warn-level CPU, a GB-scale RSS.
    private static let sampleEntry = PortEntry(
        port: 3000,
        processName: "/usr/local/bin/node",
        pid: 48213,
        projectName: "storefront",
        projectPath: "/Users/you/code/storefront",
        framework: .nextjs,
        uptime: 4 * 3600 + 12 * 60,
        health: .healthy,
        bindScope: .localOnly,
        isDockerContainer: false,
        dockerContainerName: nil,
        cpuPercent: 62.4,
        memoryRSS: 1_264_640,
        memoryPercent: 7.4
    )
}

// MARK: - Chip

struct ColumnChip: View {
    let column: PortColumn
    let placed: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: column.isLocked ? "lock.fill" : column.icon)
                .font(.system(size: 9))
            Text(column.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(placed ? Color.primary : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(placed
                ? Color.accentColor.opacity(0.16)
                : Color(NSColor.windowBackgroundColor))
        )
        .overlay(Capsule().stroke(Color.primary.opacity(placed ? 0 : 0.12)))
        .contentShape(Capsule())
    }
}
