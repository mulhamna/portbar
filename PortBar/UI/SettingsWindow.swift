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

    var body: some View {
      ScrollView {
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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                        .font(.caption.weight(.medium))
                    if updater.hasUpdate, let latest = updater.latestVersion {
                        Text("v\(latest) available — run: brew update && brew upgrade --cask portbar")
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
        .background(Color(NSColor.windowBackgroundColor))
      }
      .frame(minWidth: 560, minHeight: 320)
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    private var window: NSWindow?

    func show(watchService: WatchService) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "PortBar Settings"
            w.contentViewController = NSHostingController(
                rootView: SettingsView(watchService: watchService)
            )
            // NSHostingController sizes the window to the content's *ideal* width,
            // which the chip row and the one-line brew command push past 1000pt and
            // leaves the toggles stranded either side of a lot of nothing. The
            // content only needs enough room for the preview row's columns.
            w.setContentSize(NSSize(width: 620, height: 600))
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
