import Foundation

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
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
