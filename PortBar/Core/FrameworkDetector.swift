import Foundation

struct FrameworkDetector {
    private static var packageJsonCache: [String: [String: Any]] = [:]

    static func detect(cwd: String?, cmdline: String?, processName: String) -> Framework {
        // 1. package.json deps
        if let cwd = cwd {
            let packageJsonPath = "\(cwd)/package.json"
            if let deps = readPackageJsonDeps(at: packageJsonPath) {
                if deps["next"] != nil { return .nextjs }
                if deps["vite"] != nil { return .vite }
                if deps["@angular/core"] != nil { return .angular }
                if deps["express"] != nil { return .express }
                if deps["@remix-run/node"] != nil { return .remix }
                if deps["astro"] != nil { return .astro }
                if deps["nuxt"] != nil { return .nuxt }
            }
        }

        // 2. cmdline inspection
        if let cmdline = cmdline?.lowercased() {
            if cmdline.contains("next-server") || cmdline.contains("/next ") { return .nextjs }
            if cmdline.contains("vite") { return .vite }
            if cmdline.contains("django") || cmdline.contains("manage.py") { return .django }
            if cmdline.contains("uvicorn") || cmdline.contains("fastapi") { return .fastapi }
            if cmdline.contains("flask") { return .flask }
            if cmdline.contains("rails") || cmdline.contains("puma") { return .rails }
        }

        // 3. processName fallback
        switch processName.lowercased() {
        case "node": return .node
        case "python", "python3": return .python
        case "ruby": return .ruby
        case "docker", "com.docker": return .docker
        default: return .unknown
        }
    }

    private static func readPackageJsonDeps(at path: String) -> [String: Any]? {
        if let cached = packageJsonCache[path] {
            return cached.isEmpty ? nil : cached
        }
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            packageJsonCache[path] = [:]
            return nil
        }
        var allDeps: [String: Any] = [:]
        if let deps = json["dependencies"] as? [String: Any] {
            allDeps.merge(deps) { current, _ in current }
        }
        if let devDeps = json["devDependencies"] as? [String: Any] {
            allDeps.merge(devDeps) { current, _ in current }
        }
        packageJsonCache[path] = allDeps
        return allDeps.isEmpty ? nil : allDeps
    }
}
