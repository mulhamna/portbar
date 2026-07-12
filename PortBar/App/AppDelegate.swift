import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    // nonisolated(unsafe) lets @MainActor code write to this from assumeIsolated
    nonisolated(unsafe) private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApplicationDelegate is always called on the main thread
        MainActor.assumeIsolated {
            let watchService = WatchService()
            // ponytail: fire-and-forget banner, no tap handling yet — add a
            // UNUserNotificationCenter delegate if we ever want tap-to-open.
            watchService.onPortsChanged = { added, _ in
                guard PortBarSettings.shared.notifyOnNewPort, !added.isEmpty else { return }
                for p in added {
                    let content = UNMutableNotificationContent()
                    content.title = "New port :\(p.port)"
                    content.body  = p.framework == .unknown ? p.processName : p.framework.rawValue
                    UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                }
            }
            statusBarController = StatusBarController(watchService: watchService)
        }
    }
}
