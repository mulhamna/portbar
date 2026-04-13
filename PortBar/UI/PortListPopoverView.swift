import SwiftUI
import AppKit

// MARK: - Column widths (shared between header & rows so they align)
private enum Col {
    static let health: CGFloat   = 20   // dot
    static let port: CGFloat     = 58   // :3000
    static let process: CGFloat  = 72   // node, python3 …
    static let type: CGFloat     = 90   // Next.js, Vite …
    // project: .infinity
    static let uptime: CGFloat   = 56   // 2h 4m
}

// MARK: - Root

struct PortListPopoverView: View {
    @ObservedObject var watchService: WatchService
    @ObservedObject private var settings = PortBarSettings.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if showSettings { settingsPanel; Divider() }
            Divider()
            columnHeader
            Divider()
            portList
            Divider()
            footer
        }
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("PortBar")
                .font(.headline)

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
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(showSettings ? Color.accentColor : Color.secondary)
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

            Text("⚡ " + String(watchService.ports.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Settings panel

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SETTINGS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Watch")
                        .font(.caption.weight(.medium))
                    Text("Automatically refresh ports every 3s on launch")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.autoWatch)
                    .labelsHidden()
                    .onChange(of: settings.autoWatch) { newValue in
                        if newValue && !watchService.isWatching { watchService.startWatching() }
                        else if !newValue && watchService.isWatching { watchService.stopWatching() }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 14)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show All Ports by Default")
                        .font(.caption.weight(.medium))
                    Text("Include system & tool processes on launch")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.defaultShowAll)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 14)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                        .font(.caption.weight(.medium))
                    if updater.hasUpdate, let latest = updater.latestVersion {
                        Text("v\(latest) available — run: brew upgrade portbar")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    } else {
                        Text("Up to date")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("H")
                .frame(width: Col.health, alignment: .center)

            Text("PORT")
                .frame(width: Col.port, alignment: .center)

            Text("PROCESS")
                .frame(width: Col.process, alignment: .leading)

            Text("TYPE")
                .frame(width: Col.type, alignment: .leading)

            Text("PROJECT")
                .frame(maxWidth: .infinity, alignment: .center)

            Text("UPTIME")
                .frame(width: Col.uptime, alignment: .trailing)
                .padding(.trailing, 10)

            Text("TOOLS")
                .frame(width: 86, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Port list

    private var portList: some View {
        Group {
            if watchService.ports.isEmpty {
                Text("No active ports")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(watchService.ports) { entry in
                            PortPopoverRow(entry: entry)
                            Divider().padding(.leading, 14)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: watchService.ports.map { $0.id })
                }
                .frame(maxHeight: 400)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(String(watchService.ports.count) + " ports listening")
                .font(.caption)
                .foregroundStyle(Color.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - Row

struct PortPopoverRow: View {
    let entry: PortEntry
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {

            // H — health dot
            Circle()
                .fill(healthColor)
                .frame(width: 7, height: 7)
                .frame(width: Col.health, alignment: .center)

            // PORT
            Text(":" + String(entry.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: Col.port, alignment: .leading)
                .padding(.leading, 8)

            // PROCESS
            Text(entry.processName)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Col.process, alignment: .leading)

            // TYPE
            Text(label)
                .lineLimit(1)
                .frame(width: Col.type, alignment: .leading)

            // PROJECT
            Text(entry.projectName ?? "—")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // UP
            Text(formatUptime(entry.uptime))
                .foregroundStyle(.tertiary)
                .font(.caption.monospacedDigit())
                .frame(width: Col.uptime, alignment: .trailing)
                .padding(.trailing, 10)

            // Actions
            HStack(spacing: 4) {
                if isHTTP {
                    PortActionButton(icon: "globe", tint: .blue) { openBrowser() }
                } else {
                    Spacer().frame(width: 30)   // keep kill/copy aligned
                }
                PortActionButton(icon: "doc.on.doc", tint: Color(NSColor.secondaryLabelColor)) { copyPort() }
                PortActionButton(icon: "xmark.circle.fill", tint: .red) {
                    Task { await ProcessKiller.kill(entry: entry) }
                }
            }
            .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.1) : Color.clear)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.08), value: hovered)
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

    private var isHTTP: Bool {
        entry.port == 80 || entry.port == 443
            || (3000...3999).contains(entry.port)
            || (4000...4999).contains(entry.port)
            || (8000...8999).contains(entry.port)
    }

    private func openBrowser() {
        guard let url = URL(string: "http://localhost:\(entry.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyPort() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(":" + String(entry.port), forType: .string)
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
