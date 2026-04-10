import Foundation

enum HealthStatus {
    case healthy
    case orphaned
    case zombie
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
