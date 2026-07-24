import Foundation

enum HealthStatus {
    case healthy
    case orphaned
    case zombie
}

// Whether the listening socket is reachable only from this machine or from the LAN.
enum BindScope {
    case localOnly   // bound to 127.0.0.1 / ::1
    case exposed     // bound to 0.0.0.0 / * / :: / a specific interface — other devices can reach it
}

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
    // Stable identity so SwiftUI reuses row views across watch ticks instead of
    // rebuilding (a fresh UUID per scan caused the list to flicker). pid+port
    // matches WatchService's change-detection key: a rebind yields a new id.
    var id: String { "\(pid)-\(port)" }
    let port: Int
    let processName: String
    let pid: Int
    let projectName: String?
    let projectPath: String?
    let framework: Framework
    let uptime: TimeInterval
    let health: HealthStatus
    let bindScope: BindScope
    let isDockerContainer: Bool
    let dockerContainerName: String?
}
