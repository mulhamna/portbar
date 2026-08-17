import SwiftUI
import AppKit
import UserNotifications

// Settings live in their own window rather than inside the popover.
//
// The layout editor is roughly 600pt of content. An NSPopover is anchored to the
// menu bar item and AppKit owns its placement, so content that changes height after
// the popover is showing gets it repositioned over the menu bar — reproducible by
// opening settings, dismissing, and reopening. A window has no such anchor.
struct SettingsView: View {
    @ObservedObject private var settings = PortBarSettings.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject var watchService: WatchService

    // No ScrollView here — the window wraps it in one. Kept out so the view has a
    // real intrinsic height for the window to measure itself against.
    var body: some View {
        VStack(spacing: 0) {
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
                    Text("Show Port Count")
                        .font(.caption.weight(.medium))
                    Text("Show the number next to ⚡ in the menu bar")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.showCount)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 14)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify on New Port")
                        .font(.caption.weight(.medium))
                    Text("Banner when a new port opens while watching")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.notifyOnNewPort)
                    .labelsHidden()
                    .onChange(of: settings.notifyOnNewPort) { on in
                        if on {
                            UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }
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

            ColumnLayoutEditor(watchService: watchService)

            Divider().padding(.horizontal, 14)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                        .font(.caption.weight(.medium))
                    switch updater.state {
                    case .running:
                        Text("Upgrading the cask — PortBar will restart when it finishes")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    case .failed(let message):
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(Color.red)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    case .idle:
                        if updater.hasUpdate, let latest = updater.latestVersion {
                            Text("v\(latest) available")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        } else {
                            Text("Up to date")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                Spacer()
                if updater.hasUpdate {
                    if updater.state == .running {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(updater.state == .idle ? "Update & Restart" : "Try Again") {
                            Task { await updater.updateAndRestart() }
                        }
                        .controlSize(.small)
                    }
                }
                Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    private var window: NSWindow?

    // Left to NSHostingController, the window takes the content's *ideal* width —
    // the chip row and the brew command push that past 1000pt and strand each
    // toggle's switch a screen away from its label. This is what the preview row's
    // columns actually need.
    private static let contentWidth: CGFloat = 620

    /// Height the settings content wants at `contentWidth`, clamped to the screen.
    /// Measured rather than assumed: every constant tried here was either short
    /// enough to crop the editor or tall enough to leave dead space beneath it.
    private static func naturalHeight(of content: SettingsView) -> CGFloat {
        let probe = NSHostingView(rootView: content.frame(width: contentWidth))
        let measured = probe.fittingSize.height
        let ceiling = (NSScreen.main?.visibleFrame.height ?? 900) - 80
        guard measured > 100 else { return min(600, ceiling) }
        return min(measured, ceiling)
    }

    func show(watchService: WatchService) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "PortBar Settings"
            let content = SettingsView(watchService: watchService)
            w.contentViewController = NSHostingController(rootView: ScrollView { content })
            w.contentMinSize = NSSize(width: Self.contentWidth, height: 300)
            w.setContentSize(NSSize(
                width: Self.contentWidth,
                height: Self.naturalHeight(of: content)
            ))
            w.isReleasedWhenClosed = false   // reopened later; releasing would dangle
            w.center()
            window = w
        }
        // LSUIElement apps are not active by default, so the window would open behind
        // whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
