# PortBar — CLAUDE.md

> This file is the single source of truth for Claude Code. Read it fully before writing any code.

## Smoke Test Requirement

**Every code change must be followed by a smoke test before shipping.** No exceptions.

Steps:
1. Build: `xcodebuild -project PortBar.xcodeproj -scheme PortBar -configuration Debug build`
2. Kill any running instance: `pkill -x PortBar`
3. Launch: `open <DerivedData>/Build/Products/Debug/PortBar.app`
4. Verify process is alive: `pgrep -x PortBar`
5. Start a test port: `python3 -m http.server 8888 &`
6. Wait ≤3s — confirm `⚡ 1` appears in menu bar and `:8888 Python` row is visible
7. Kill test port: `kill <pid>`
8. Confirm count drops back to `⚡ 0`
9. Kill debug instance: `pkill -x PortBar`

Only proceed to DMG/release if all steps pass.

## What is PortBar?

A native macOS menu bar app that shows all active ports on the machine.

**Core user flow:**
1. PortBar icon sits in the macOS menu bar showing active port count (e.g. `⚡ 5`)
2. User clicks → **NSPopover** appears listing every listening port with process name, PID, project folder, detected framework, uptime, and health status
3. Each port row has inline action buttons: **Kill Process** (`✕`), **Open in Browser** (`🌐`, if HTTP), **Copy Port** (`📋`)
4. A **Watch** toggle enables real-time polling — icon updates when ports open/close
5. Color coding: green = healthy, yellow = orphaned, red = zombie

---

## Tech Stack

| Layer        | Choice                                 | Reason                                               |
| ------------ | -------------------------------------- | ---------------------------------------------------- |
| Language     | Swift 5.9+                             | Native, no runtime deps, small bundle                |
| Min OS       | macOS 14 (Sonoma)                      | SwiftUI menu bar APIs stable here                    |
| UI framework | SwiftUI + AppKit (NSStatusItem)        | Menu bar requires AppKit; SwiftUI for popover content |
| Data layer   | Shell: `lsof`, `ps`, `docker ps`       | ~0.2s, no privileges needed                          |
| Distribution | GitHub Releases (.dmg) + Homebrew Cask | Max reach, easy install for non-devs                 |
| Build        | Xcode project (no SwiftPM for now)     | Easier for contributors; avoids entitlement friction |

**No third-party dependencies.** Zero-dep for trust and simplicity.

---

## Repository Structure

```
PortBar/
├── CLAUDE.md
├── README.md
├── LICENSE                          ← MIT
├── .gitignore
├── PortBar.xcodeproj/
│   └── project.pbxproj
└── PortBar/
    ├── App/
    │   ├── main.swift               ← NSApplication entry, no Dock icon
    │   ├── AppDelegate.swift        ← lifecycle, creates WatchService + StatusBarController
    │   └── StatusBarController.swift← owns NSStatusItem + NSPopover, Combine observers
    ├── Core/
    │   ├── Models.swift             ← PortEntry, Framework enum, HealthStatus enum
    │   ├── ShellRunner.swift        ← async shell() helper (Process + Pipe)
    │   ├── PortScanner.swift        ← runs lsof + ps + docker ps, returns [PortEntry]
    │   ├── FrameworkDetector.swift  ← maps process cwd/cmdline → Framework enum
    │   ├── ProcessKiller.swift      ← NSAlert confirmation, SIGTERM → SIGKILL
    │   ├── WatchService.swift       ← Timer-based polling, publishes via Combine
    │   └── Settings.swift           ← PortBarSettings (displayMode UserDefaults)
    ├── UI/
    │   ├── MenuBuilder.swift        ← builds NSMenu (grouped mode + action targets)
    │   ├── PortListPopoverView.swift ← primary UI: SwiftUI popover with column layout
    │   └── PortScrollRowView.swift  ← AppKit row view (used in flat NSMenu embed, legacy)
    ├── Resources/
    │   ├── Assets.xcassets/
    │   │   └── AppIcon.appiconset/
    │   └── PortBar.entitlements
    └── Info.plist
```

---

## Primary UI: NSPopover + SwiftUI (PortListPopoverView.swift)

The **main UI is an NSPopover** containing a SwiftUI view — not a dropdown NSMenu. The popover is 520px wide and has:

1. **Toolbar** — app name, watch toggle button, refresh button, port count badge
2. **Column header** — `H | PORT | TYPE | PROJECT | UP | (actions)`
3. **Scrollable port list** — `LazyVStack`, max height 400px
4. **Footer** — port count + Quit button

Column widths are defined in a shared `Col` enum so header and rows stay aligned:

```swift
private enum Col {
    static let health: CGFloat  = 20   // dot
    static let port: CGFloat    = 58   // :3000
    static let type: CGFloat    = 96   // Next.js, Vite …
    // project: .infinity
    static let uptime: CGFloat  = 42   // 2h 4m
}
```

Each `PortPopoverRow` shows:
- Health dot (green/yellow/red `Circle`)
- Port number as `":" + String(entry.port)` — **must use `String(port)`, NOT `"\(port)"` via SwiftUI interpolation** (locale formatting bug causes `:3.000`)
- TYPE label: `entry.framework.rawValue` if known, otherwise `entry.projectName ?? entry.processName`
- PROJECT (truncated middle, `.infinity` width)
- Uptime (`formatUptime()`)
- Action buttons: `🌐` (HTTP only), `📋`, `✕`

### NSPopover trigger

`StatusBarController` always uses NSPopover (no NSMenu as primary UI):

```swift
private func rebuildUI() {
    statusItem.menu = nil
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePopover(_:))
}
```

The popover is lazily created on first click and reused (`.transient` behavior).

---

## Settings (Settings.swift)

```swift
final class PortBarSettings: ObservableObject {
    static let shared = PortBarSettings()
    enum DisplayMode: String, CaseIterable {
        case grouped = "grouped"
        case flat    = "flat"
        var label: String { ... }
    }
    @Published var displayMode: DisplayMode  // persisted in UserDefaults "pb.displayMode"
}
```

`StatusBarController` observes `$displayMode` — on change it closes/nils the popover and calls `rebuildUI()`.

> Note: With the popover as primary UI, `displayMode` affects `MenuBuilder` (used for the Settings submenu layout toggle), but the main interactive UI is always the popover.

---

## Models (Models.swift)

```swift
enum HealthStatus {
    case healthy    // process running normally
    case orphaned   // parent PID is dead (ppid = 1 or missing)
    case zombie     // process in Z state
}

enum Framework: String {
    case nextjs = "Next.js", vite = "Vite", express = "Express"
    case remix = "Remix", astro = "Astro", angular = "Angular", nuxt = "Nuxt"
    case django = "Django", fastapi = "FastAPI", flask = "Flask"
    case rails = "Rails"
    case postgresql = "PostgreSQL", redis = "Redis", mongodb = "MongoDB"
    case localstack = "LocalStack", nginx = "nginx", mysql = "MySQL"
    case node = "Node.js", python = "Python", ruby = "Ruby"
    case docker = "Docker"
    case unknown = "Unknown"
}

struct PortEntry: Identifiable {
    let id = UUID()
    let port: Int
    let processName: String
    let pid: Int
    let projectName: String?
    let projectPath: String?
    let framework: Framework
    let uptime: TimeInterval
    let health: HealthStatus
    let isDockerContainer: Bool
    let dockerContainerName: String?
}
```

---

## PortScanner (PortScanner.swift)

Three shell calls, all batched for performance.

### Call 1 — listening ports
```bash
lsof -iTCP -sTCP:LISTEN -n -P
```

### Call 2 — process details
```bash
ps -o pid=,comm=,ppid=,stat=,etime= -p <pids>
```

### Call 3 — working directories
```bash
lsof -d cwd -a -p <pids> -Fn
```

### Call 3b — Docker (conditional)
```bash
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
```

### Filtering
Skip known system processes: `Spotify`, `Raycast`, `com.apple.*`, `UserEventAgent`, `rapportd`, `ControlCenter`, `mDNSResponder`, etc.

**Do NOT filter on `port > 49151` with unknown framework** — this was too aggressive and caused fewer ports to show than port-whisperer.

### Health
- `stat` contains `Z` → `.zombie`
- `ppid == 1` AND dev runtime → `.orphaned`
- otherwise → `.healthy`

---

## FrameworkDetector (FrameworkDetector.swift)

Detection priority (first match wins):

1. `package.json` deps: `next` → `.nextjs`, `vite` → `.vite`, `@angular/core` → `.angular`, `express` → `.express`, `@remix-run/node` → `.remix`, `astro` → `.astro`, `nuxt` → `.nuxt`
2. cmdline: `next`/`next-server`, `vite`, `django`/`manage.py`, `uvicorn`/`fastapi`, `flask`, `rails`/`puma`
3. processName: `node` → `.node`, `python`/`python3` → `.python`, `ruby` → `.ruby`, `docker`/`com.docker` → `.docker`
4. `.unknown`

Cache `package.json` reads by path using a static dictionary.

---

## WatchService (WatchService.swift)

```swift
@MainActor
class WatchService: ObservableObject {
    @Published var ports: [PortEntry] = []
    @Published var isWatching: Bool = false
    func startWatching(interval: TimeInterval = 3.0) { ... }
    func stopWatching() { ... }
    func refresh() async { ... }
}
```

Poll interval: **3 seconds** when watching, manual otherwise.

---

## StatusBarController (StatusBarController.swift)

### Title logic
- Format: `⚡ N` (N = port count)
- Color via `NSAttributedString`: red if any zombie, yellow if any orphaned, label color otherwise
- When watching: prepend `◉ `

### Combine observers
Observes `watchService.$ports`, `watchService.$isWatching`, and `PortBarSettings.shared.$displayMode`.

---

## ProcessKiller (ProcessKiller.swift)

```swift
struct ProcessKiller {
    static func kill(entry: PortEntry) async
}
```

- Confirm with `NSAlert` first
- `Darwin.kill(pid, SIGTERM)` → wait 3s → `Darwin.kill(pid, SIGKILL)` if still alive
- No `sudo` — only kills user-owned processes
- Triggers `WatchService.refresh()` after kill

---

## MenuBuilder (MenuBuilder.swift)

Builds the NSMenu for the grouped display mode (legacy/settings). Key parts:

- **Grouped categories:** DEV SERVERS, DATABASES, DOCKER, OTHER
- Max 6 inline per category, rest collapse to `▸ N more...` submenu
- Shared helpers (used by both grouped rows and flat scroll rows):
  - `static func makePortSubmenu(entry:) -> NSMenu` — Kill / Open in Browser / Copy / Reveal in Finder
  - `static func buildPortTitle(entry:) -> NSAttributedString` — health dot + port + label + project + uptime
- Action targets (singletons): `DisplayModeTarget`, `WatchToggleTarget`, `RefreshTarget`, `KillTarget`, `OpenBrowserTarget`, `CopyTarget`, `RevealTarget`

---

## Shell Helper (ShellRunner.swift)

```swift
func shell(_ command: String) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        }
        do { try process.run() } catch { continuation.resume(throwing: error) }
    }
}
```

---

## Uptime Parsing

`ps -o etime=` format: `[[DD-]HH:]MM:SS`

```swift
func parseEtime(_ etime: String) -> TimeInterval { ... }
func formatUptime(_ seconds: TimeInterval) -> String {
    // "45s", "2h 40m", "1d 9h"
}
```

---

## Known Gotchas

- **SwiftUI locale formatting:** `Text("\(intValue)")` triggers `LocalizedStringKey` which adds thousand separators (`:3.000`). Always use `":" + String(entry.port)` or `String(intValue)` directly.
- **`@MainActor` + `NSApplicationDelegate`:** `NSApplicationDelegate` callbacks run on main thread but aren't `@MainActor`. Use `MainActor.assumeIsolated {}` inside `applicationDidFinishLaunching`. Store `StatusBarController` with `nonisolated(unsafe)`.
- **NSScrollView-in-NSMenuItem:** NSMenu intercepts all scroll wheel and click events during tracking — embedded interactive scroll views don't work. Use NSPopover instead.

---

## Entitlements & Permissions

`PortBar/Resources/PortBar.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

App sandbox **must be OFF** — `lsof` and `ps` cannot run sandboxed.

---

## Info.plist

```xml
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
```

---

## Build & Run

```bash
open PortBar.xcodeproj

# CLI build
xcodebuild -project PortBar.xcodeproj -scheme PortBar -configuration Debug build

# Release DMG
xcodebuild -project PortBar.xcodeproj -scheme PortBar -configuration Release build
# then hdiutil / create-dmg to package
```

---

## Coding Conventions

- `actor PortScanner` for concurrent shell calls
- `@MainActor` on `WatchService`, `StatusBarController`, and all UI classes
- No force unwraps — `guard let` / `if let` everywhere
- Zero third-party dependencies
- `async/await` over callbacks
- Shell output: trim whitespace, split by lines, handle empty output gracefully

---

## Out of Scope (v1)

- Linux / Windows
- Remote machines / SSH port forwarding
- Network traffic monitoring
- Port history / logging
- Settings UI beyond display mode toggle
