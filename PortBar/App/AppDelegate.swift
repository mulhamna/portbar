import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // nonisolated(unsafe) lets @MainActor code write to this from assumeIsolated
    nonisolated(unsafe) private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApplicationDelegate is always called on the main thread
        MainActor.assumeIsolated {
            let watchService = WatchService()
            statusBarController = StatusBarController(watchService: watchService)
        }
    }
}
