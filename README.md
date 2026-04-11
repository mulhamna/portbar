# PortBar

A native macOS menu bar app that shows every active listening port on your machine — with process name, framework detection, project folder, uptime, and health status.

```
⚡ 5
```

Click the icon → a panel drops down listing all your ports. Kill a runaway process, open it in the browser, or copy the port — all without touching the terminal.

---

## Features

- **Live port list** — shows every TCP port in LISTEN state, sorted by port number
- **Framework detection** — recognizes Next.js, Vite, Express, Django, FastAPI, Flask, Rails, PostgreSQL, Redis, MongoDB, nginx, and more
- **Health status** — color-coded dot per port: 🟢 healthy · 🟡 orphaned · 🔴 zombie
- **Watch mode** — polls every 3 seconds, menu bar title updates automatically
- **Kill process** — confirms with a dialog, sends SIGTERM → SIGKILL after 3 seconds
- **Open in browser** — one click for HTTP ports (80, 443, 3xxx, 4xxx, 8xxx)
- **Copy port** — copies `:3000` style to clipboard
- **Reveal in Finder** — shows the project directory for any port
- Zero network calls — everything runs locally via `lsof` and `ps`

---

## Install

### Direct download

1. Download `PortBar.dmg` from [Releases](../../releases)
2. Open the DMG and drag **PortBar.app** to Applications
3. Launch it — the `⚡` icon appears in your menu bar

---

## Usage

| Action | How |
|---|---|
| See all ports | Click `⚡ N` in the menu bar |
| Enable watch mode | Click the **eye** button in the panel toolbar |
| Manual refresh | Click the **↺** button |
| Kill a process | Click the red **✕** button on a port row |
| Open in browser | Click the **🌐** button (HTTP ports only) |
| Copy port | Click the **📋** button |
| Quit | Footer → Quit |

---

## How it works

PortBar makes exactly **3 shell calls** per scan — same strategy as [port-whisperer](https://github.com/LarsenCundric/port-whisperer):

```bash
# 1. Find every TCP port in LISTEN state
lsof -iTCP -sTCP:LISTEN -n -P

# 2. Get process details for all found PIDs in one call
ps -o pid=,comm=,ppid=,stat=,etime= -p <pids>

# 3. Resolve working directories for framework detection
lsof -d cwd -a -p <pids> -Fn
```

If Docker is running, a fourth call fetches container names and images:

```bash
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
```

A typical scan takes ~0.2 seconds.

### Framework detection

For each port, PortBar checks (in order):

1. **`package.json`** — reads `dependencies` + `devDependencies` to identify JS frameworks
2. **Process command line** — detects Django, FastAPI, Flask, Rails, Vite, Next.js by argv
3. **Process name** — falls back to `node`, `python`, `ruby`, `docker`

`package.json` reads are cached per directory to avoid redundant I/O.

### Health status

| Color | Meaning |
|---|---|
| 🟢 Green | Process running normally |
| 🟡 Yellow | Orphaned — parent process is gone (ppid = 1) |
| 🔴 Red | Zombie — process is in Z state |

---

## Privacy & Security

- **No network calls.** PortBar never phones home or contacts any external server.
- **No disk scanning.** It only reads `package.json` in the working directory of each process it finds.
- **No elevated privileges.** PortBar runs as your user. It can only kill processes you own.
- **App Sandbox is off** — required because `lsof` and `ps` cannot run inside the macOS sandbox. This is standard for developer tools (same as many terminal apps and developer utilities). You can inspect the source and build it yourself.

---

## Building from source

Requirements: **Xcode 15+**, macOS 14+

```bash
git clone https://github.com/mulhamna/portbar
cd portbar
open PortBar.xcodeproj
```

Press **⌘R** to build and run, or use the CLI:

```bash
xcodebuild -project PortBar.xcodeproj \
           -scheme PortBar \
           -configuration Debug \
           build
open build/Debug/PortBar.app
```

No dependencies to install — zero third-party packages.

---

## Contributing

Pull requests welcome. A few ground rules:

- Keep it zero-dependency
- macOS 14+ only
- The app sandbox stays off (required for `lsof`)
- Read `CLAUDE.md` before making significant changes — it documents the architecture decisions

---

## License

MIT — see [LICENSE](LICENSE)
