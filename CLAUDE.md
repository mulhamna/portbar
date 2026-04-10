# PortBar — CLAUDE.md

> This file is the single source of truth for Claude Code. Read it fully before writing any code.

## What is PortBar?

A native macOS menu bar app that shows all active ports on the machine — inspired by [port-whisperer](https://github.com/LarsenCundric/port-whisperer) for the data layer and [CodexBar](https://github.com/steipete/codexbar) for the menu bar UX pattern.

**Core user flow:**
1. PortBar icon sits in the macOS menu bar showing active port count (e.g. `⚡ 5`)
2. User clicks → dropdown appears listing every listening port with process name, PID, project folder, detected framework, uptime, and health status
3. Each port row has actions: **Kill Process**, **Open in Browser** (if HTTP), **Copy Port**
4. A **Watch** toggle enables real-time polling — icon updates when ports open/close
5. Color coding matches port-whisperer: green = healthy, yellow = orphaned, red = zombie

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Language | Swift 5.9+ | Native, no runtime deps, small bundle |
| Min OS | macOS 14 (Sonoma) | SwiftUI menu bar APIs stable here |
| UI framework | SwiftUI + AppKit (NSStatusItem) | Menu bar requires AppKit; SwiftUI for menu content |
| Data layer | Shell: `lsof`, `ps`, `docker ps` | Same 3 calls as port-whisperer, ~0.2s |
| Distribution | GitHub Releases (.dmg) + Homebrew Cask | Max reach, easy install for non-devs |
| Build | Xcode project (no SwiftPM for now) | Easier for contributors; avoids entitlement friction |

**No third-party dependencies.** Keep it zero-dep for trust and simplicity.

---

## Repository Structure

```
PortBar/
├── CLAUDE.md                        ← you are here
├── README.md
├── LICENSE                          ← MIT
├── .gitignore
├── PortBar.xcodeproj/
│   └── project.pbxproj
└── PortBar/
    ├── App/
    │   ├── main.swift               ← NSApplication entry, no Dock icon
    │   ├── AppDelegate.swift        ← NSStatusItem setup, lifecycle
    │   └── StatusBarController.swift← owns NSStatusItem, coordinates everything
    ├── Core/
    │   ├── Models.swift             ← PortEntry, Framework enum, HealthStatus enum
    │   ├── PortScanner.swift        ← runs lsof + ps + docker ps, returns [PortEntry]
    │   ├── FrameworkDetector.swift  ← maps process cwd/cmdline → Framework enum
    │   ├── ProcessKiller.swift      ← sends SIGTERM/SIGKILL by PID, requires user confirmation
    │   └── WatchService.swift       ← Timer-based polling, publishes changes via Combine
    ├── UI/
    │   ├── MenuBuilder.swift        ← builds NSMenu from [PortEntry]
    │   ├── PortRowView.swift        ← SwiftUI view for a single port row (used in popover alt)
    │   └── AboutView.swift          ← simple about panel
    ├── Resources/
    │   ├── Assets.xcassets/
    │   │   └── AppIcon.appiconset/
    │   └── PortBar.entitlements
    └── Info.plist
```

---

## Models (Models.swift)

```swift
// Health of the process
enum HealthStatus {
    case healthy    // process running normally
    case orphaned   // parent PID is dead (ppid = 1 or missing)
    case zombie     // process in Z state
}

// Detected framework/runtime
enum Framework: String {
    // Node / JS
    case nextjs = "Next.js"
    case vite = "Vite"
    case express = "Express"
    case remix = "Remix"
    case astro = "Astro"
    case angular = "Angular"
    case nuxt = "Nuxt"
    // Python
    case django = "Django"
    case fastapi = "FastAPI"
    case flask = "Flask"
    // Ruby
    case rails = "Rails"
    // Docker
    case postgresql = "PostgreSQL"
    case redis = "Redis"
    case mongodb = "MongoDB"
    case localstack = "LocalStack"
    case nginx = "nginx"
    case mysql = "MySQL"
    // Generic
    case node = "Node.js"
    case python = "Python"
    case ruby = "Ruby"
    case docker = "Docker"
    case unknown = "Unknown"
}

struct PortEntry: Identifiable {
    let id = UUID()
    let port: Int
    let processName: String
    let pid: Int
    let projectName: String?    // basename of cwd, nil if unresolvable
    let projectPath: String?    // full cwd path
    let framework: Framework
    let uptime: TimeInterval    // seconds, derived from ps -o etime
    let health: HealthStatus
    let isDockerContainer: Bool
    let dockerContainerName: String?  // e.g. "backend-postgres-1"
}
```

---

## PortScanner (PortScanner.swift)

Performs exactly **3 shell calls**, batched, same strategy as port-whisperer.

### Call 1 — Find listening ports
```bash
lsof -iTCP -sTCP:LISTEN -n -P
```
Parse output: extract PID and port number per line. Skip duplicates (same PID+port).

### Call 2 — Batch process details
```bash
ps -o pid=,comm=,ppid=,stat=,etime= -p <comma-separated PIDs>
```
Single call for all PIDs. Parse each line → processName, ppid, stat (Z = zombie), etime (parse to TimeInterval).

### Call 3 — Batch working directory
```bash
lsof -d cwd -a -p <comma-separated PIDs> -Fn
```
Parse `n` lines → map PID to cwd path. Call `FrameworkDetector` with cwd.

### Call 3b — Docker (conditional, only if any PID matches `com.docker`)
```bash
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
```
Map host port → container name and image → override framework detection for Docker ports.

### Health detection logic
- `stat` contains `Z` → `.zombie`
- `ppid == 1` AND process is a dev runtime (node, python, ruby) → `.orphaned`
- otherwise → `.healthy`

### Filtering
Default (non `--all`) mode: skip ports where processName matches system app heuristics:
- Known system process names: `Spotify`, `Raycast`, `com.apple.*`, `UserEventAgent`, `rapportd`, `ControlCenter`
- Ports > 49151 (ephemeral range) with no known framework → skip
- Keep anything matching a known framework or docker

### Public API
```swift
actor PortScanner {
    func scan(includeAll: Bool = false) async throws -> [PortEntry]
}
```

---

## FrameworkDetector (FrameworkDetector.swift)

```swift
struct FrameworkDetector {
    /// Given a working directory path and process command line, return Framework
    static func detect(cwd: String?, cmdline: String?, processName: String) -> Framework
}
```

Detection priority (first match wins):

1. **package.json deps** — read `\(cwd)/package.json`, check `dependencies` + `devDependencies`:
   - `next` → `.nextjs`
   - `vite` → `.vite`
   - `@angular/core` → `.angular`
   - `express` → `.express`
   - `@remix-run/node` → `.remix`
   - `astro` → `.astro`
   - `nuxt` → `.nuxt`

2. **cmdline inspection**:
   - contains `next` or `next-server` → `.nextjs`
   - contains `vite` → `.vite`
   - contains `django` or `manage.py` → `.django`
   - contains `uvicorn` or `fastapi` → `.fastapi`
   - contains `flask` → `.flask`
   - contains `rails` or `puma` → `.rails`

3. **processName fallback**:
   - `node` → `.node`
   - `python` or `python3` → `.python`
   - `ruby` → `.ruby`
   - `docker` or `com.docker` → `.docker`

4. → `.unknown`

**Performance:** Cache package.json reads by path. Use `FileManager` not shell.

---

## WatchService (WatchService.swift)

```swift
@MainActor
class WatchService: ObservableObject {
    @Published var ports: [PortEntry] = []
    @Published var isWatching: Bool = false

    private var timer: Timer?
    private let scanner = PortScanner()
    var onPortsChanged: (([PortEntry], [PortEntry]) -> Void)?  // (added, removed)

    func startWatching(interval: TimeInterval = 3.0) { ... }
    func stopWatching() { ... }
    func refresh() async { ... }  // single manual scan
}
```

- Default poll interval: **3 seconds** when watch mode on, **manual** otherwise.
- On change: diff previous vs current `ports` by port number → call `onPortsChanged`.
- `onPortsChanged` triggers a macOS `NSUserNotification` (or `UNUserNotificationCenter`) for added/removed ports.

---

## StatusBarController (StatusBarController.swift)

```swift
class StatusBarController {
    private var statusItem: NSStatusItem
    private var watchService: WatchService
    private var menu: NSMenu

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // ...
    }
}
```

### Icon / title logic (matches port-whisperer style)
- **Title format:** `⚡ N` where N = number of active (non-system) ports
- **Color:** use `NSAttributedString` with:
  - Green if all ports healthy
  - Yellow if any orphaned
  - Red if any zombie
- When `isWatching = true`, prepend `◉ ` to title

### Menu structure (built by MenuBuilder)
```
⚡ 5                            ← status item title
─────────────────────────
◉ Watch Mode          [toggle]  ← NSMenuItem with state
↻ Refresh                       ← triggers manual scan
─────────────────────────
:3000  Next.js   frontend  1d 9h   ● healthy  ▶
:3001  Next.js   preview    2h     ● healthy  ▶
:5432  PostgreSQL backend-pg 10d   ● healthy  ▶
─────────────────────────
Show All Ports        [toggle]
─────────────────────────
About PortBar
Quit
```

Each port row `▶` expands a submenu:
```
Kill Process (PID 42872)
Open in Browser          ← only shown for ports 80/443/3xxx/4xxx/8xxx
Copy :3000
─────────────────
/Users/you/projects/frontend  ← greyed out, click to reveal in Finder
Next.js · 1d 9h · PID 42872
```

---

## ProcessKiller (ProcessKiller.swift)

```swift
struct ProcessKiller {
    /// Shows NSAlert confirmation then sends SIGTERM. If process still alive after 3s, sends SIGKILL.
    static func kill(entry: PortEntry) async
}
```

- **Always confirm** with `NSAlert` before killing. Alert text: `"Kill \(entry.processName) on :\(entry.port)?"` with detail showing project name.
- Send `SIGTERM` first (`kill(pid, SIGTERM)`).
- Wait 3 seconds, check if PID still exists (`kill(pid, 0)` returns 0 if alive).
- If still alive, send `SIGKILL`.
- Do NOT use `sudo`. PortBar only kills processes owned by the current user.
- After kill, trigger a `WatchService.refresh()`.

---

## Entitlements & Permissions

File: `PortBar/Resources/PortBar.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Required to run lsof and ps as shell subprocesses -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

**App sandbox must be OFF.** `lsof` and `ps` cannot run inside the sandbox. This is standard for developer tools (CodexBar does the same). Note this clearly in README so users trust it.

---

## Info.plist keys

```xml
<key>LSUIElement</key>
<true/>                    <!-- No Dock icon, menu bar only -->

<key>NSPrincipalClass</key>
<string>NSApplication</string>

<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

---

## Shell Execution Helper

Create a single reusable helper used by PortScanner everywhere:

```swift
func shell(_ command: String) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = Pipe()  // suppress stderr
        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
```

---

## Uptime Parsing

`ps -o etime=` returns format `[[DD-]HH:]MM:SS`. Parse to `TimeInterval`:

```swift
func parseEtime(_ etime: String) -> TimeInterval {
    // examples: "01:23", "1:01:23", "2-01:23:45"
    // split on "-" first for days, then ":" for H:M:S
}

func formatUptime(_ seconds: TimeInterval) -> String {
    // return "2h 40m", "1d 9h", "45s" etc — match port-whisperer style
}
```

---

## Build & Run Instructions (for Claude Code)

```bash
# Open in Xcode
open PortBar.xcodeproj

# Or build from CLI (requires Xcode Command Line Tools)
xcodebuild -project PortBar.xcodeproj \
           -scheme PortBar \
           -configuration Debug \
           build

# Run
open build/Debug/PortBar.app
```

To create a release `.dmg` for GitHub Releases:
```bash
xcodebuild -project PortBar.xcodeproj -scheme PortBar -configuration Release build
# then use create-dmg or hdiutil to package
```

---

## Coding Conventions

- **Actors** for `PortScanner` (concurrent shell calls are safe this way)
- **`@MainActor`** on `WatchService` and all UI-touching classes
- **No force unwraps** — use `guard let` or `if let` everywhere
- **No third-party packages** — zero dependencies
- Prefer `async/await` over callbacks
- All shell output parsing: trim whitespace, split by lines, handle empty output gracefully
- File names match the class/struct name exactly

---

## What to Build First (Suggested Order)

1. `Models.swift` — define all types
2. `shell()` helper in a `ShellRunner.swift` utility file
3. `FrameworkDetector.swift` — pure logic, easy to unit test
4. `PortScanner.swift` — core data, test output in a CLI target first
5. `WatchService.swift` — wraps scanner with timer
6. `AppDelegate.swift` + `StatusBarController.swift` — wire up NSStatusItem
7. `MenuBuilder.swift` — build the NSMenu from [PortEntry]
8. `ProcessKiller.swift` — add kill action last (destructive, needs care)

---

## README Outline (to write after core is working)

- What it is + screenshot
- Install: Homebrew Cask / direct .dmg
- Usage: click icon, watch mode, kill
- How it works (the 3 shell calls)
- Privacy: no network, no disk scanning beyond cwd resolution
- Why no sandbox: explain lsof requirement
- Contributing
- License: MIT

---

## Out of Scope (do not implement)

- Linux support (macOS only, `lsof` behavior differs)
- Windows
- Remote machines / SSH port forwarding detection
- Network traffic monitoring
- Port history / logging
- Settings UI (keep it simple for v1)
