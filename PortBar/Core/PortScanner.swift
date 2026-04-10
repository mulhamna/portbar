import Foundation

actor PortScanner {
    func scan(includeAll: Bool = false) async throws -> [PortEntry] {
        // Call 1: Find listening ports
        let lsofOutput = try await shell("lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null")
        let pidPortPairs = parseLsofListen(lsofOutput)
        guard !pidPortPairs.isEmpty else { return [] }

        let pids = Array(Set(pidPortPairs.map { $0.pid }))
        let pidList = pids.map(String.init).joined(separator: ",")

        // Call 2: Batch process details
        let psOutput = try await shell("ps -o pid=,comm=,ppid=,stat=,etime= -p \(pidList) 2>/dev/null")
        let processInfos = parsePs(psOutput)

        // Call 3: Batch working directories
        let cwdOutput = try await shell("lsof -d cwd -a -p \(pidList) -Fn 2>/dev/null")
        let cwdMap = parseCwd(cwdOutput)

        // Call 3b: Docker (conditional)
        let hasDocker = processInfos.values.contains {
            $0.name.lowercased().contains("docker") || $0.name == "com.docker"
        }
        var dockerPortMap: [Int: (name: String, image: String)] = [:]
        if hasDocker {
            let dockerOutput = (try? await shell("docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null")) ?? ""
            dockerPortMap = parseDocker(dockerOutput)
        }

        // Build entries
        var seen = Set<String>()
        var entries: [PortEntry] = []

        for pair in pidPortPairs {
            let key = "\(pair.pid)-\(pair.port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let info = processInfos[pair.pid] else { continue }

            let cwd = cwdMap[pair.pid]
            let framework: Framework
            let isDocker: Bool
            let dockerName: String?

            if let dockerInfo = dockerPortMap[pair.port] {
                framework = detectDockerFramework(image: dockerInfo.image)
                isDocker = true
                dockerName = dockerInfo.name
            } else {
                framework = FrameworkDetector.detect(cwd: cwd, cmdline: nil, processName: info.name)
                isDocker = false
                dockerName = nil
            }

            if !includeAll && shouldSkip(processName: info.name, port: pair.port, framework: framework) {
                continue
            }

            let health = determineHealth(stat: info.stat, ppid: info.ppid, processName: info.name)
            let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

            entries.append(PortEntry(
                port: pair.port,
                processName: URL(fileURLWithPath: info.name).lastPathComponent,
                pid: pair.pid,
                projectName: projectName,
                projectPath: cwd,
                framework: framework,
                uptime: parseEtime(info.etime),
                health: health,
                isDockerContainer: isDocker,
                dockerContainerName: dockerName
            ))
        }

        return entries.sorted { $0.port < $1.port }
    }

    // MARK: - Parsers

    private func parseLsofListen(_ output: String) -> [(pid: Int, port: Int)] {
        var results: [(pid: Int, port: Int)] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
            let nameField = String(parts[8])
            // Use lastIndex to handle IPv6 addresses like [::1]:3000
            guard let colonIdx = nameField.lastIndex(of: ":"),
                  let port = Int(nameField[nameField.index(after: colonIdx)...]) else { continue }
            results.append((pid: pid, port: port))
        }
        return results
    }

    private struct ProcessInfo {
        let name: String
        let ppid: Int
        let stat: String
        let etime: String
    }

    private func parsePs(_ output: String) -> [Int: ProcessInfo] {
        var result: [Int: ProcessInfo] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[2]) else { continue }
            result[pid] = ProcessInfo(
                name: String(parts[1]),
                ppid: ppid,
                stat: String(parts[3]),
                etime: String(parts[4]).trimmingCharacters(in: .whitespaces)
            )
        }
        return result
    }

    private func parseCwd(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var currentPid: Int?
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                currentPid = pid
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    private func parseDocker(_ output: String) -> [Int: (name: String, image: String)] {
        var result: [Int: (name: String, image: String)] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            let image = parts[1]
            let ports = parts[2]
            // e.g. "0.0.0.0:5432->5432/tcp, :::5432->5432/tcp"
            for mapping in ports.components(separatedBy: ",") {
                let trimmed = mapping.trimmingCharacters(in: .whitespaces)
                if let colonIdx = trimmed.lastIndex(of: ":"),
                   let arrowIdx = trimmed.range(of: "->")?.lowerBound,
                   colonIdx < arrowIdx {
                    let portStr = String(trimmed[trimmed.index(after: colonIdx)..<arrowIdx])
                    if let port = Int(portStr) {
                        result[port] = (name: name, image: image)
                    }
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    private func detectDockerFramework(image: String) -> Framework {
        let img = image.lowercased()
        if img.contains("postgres") { return .postgresql }
        if img.contains("redis") { return .redis }
        if img.contains("mongo") { return .mongodb }
        if img.contains("nginx") { return .nginx }
        if img.contains("mysql") { return .mysql }
        if img.contains("localstack") { return .localstack }
        return .docker
    }

    private func shouldSkip(processName: String, port: Int, framework: Framework) -> Bool {
        let systemProcesses: Set<String> = [
            "Spotify", "Raycast", "UserEventAgent", "rapportd", "ControlCenter"
        ]
        if systemProcesses.contains(processName) { return true }
        if processName.hasPrefix("com.apple.") { return true }
        if port > 49151 && framework == .unknown { return true }
        return false
    }

    private func determineHealth(stat: String, ppid: Int, processName: String) -> HealthStatus {
        if stat.contains("Z") { return .zombie }
        let devRuntimes: Set<String> = ["node", "python", "python3", "ruby"]
        if ppid == 1 && devRuntimes.contains(processName.lowercased()) { return .orphaned }
        return .healthy
    }
}

// MARK: - Uptime helpers (global, used by MenuBuilder too)

func parseEtime(_ etime: String) -> TimeInterval {
    var total: TimeInterval = 0
    let dayParts = etime.components(separatedBy: "-")
    var timePart = etime

    if dayParts.count == 2, let days = Double(dayParts[0]) {
        total += days * 86400
        timePart = dayParts[1]
    }

    let components = timePart.components(separatedBy: ":")
    switch components.count {
    case 3:
        total += (Double(components[0]) ?? 0) * 3600
        total += (Double(components[1]) ?? 0) * 60
        total += Double(components[2]) ?? 0
    case 2:
        total += (Double(components[0]) ?? 0) * 60
        total += Double(components[1]) ?? 0
    case 1:
        total += Double(components[0]) ?? 0
    default:
        break
    }
    return total
}

func formatUptime(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    let remainM = m % 60
    if h < 24 { return remainM > 0 ? "\(h)h \(remainM)m" : "\(h)h" }
    let d = h / 24
    let remainH = h % 24
    return remainH > 0 ? "\(d)d \(remainH)h" : "\(d)d"
}
