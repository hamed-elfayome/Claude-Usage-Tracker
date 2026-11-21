import Foundation

/// Reads the signed-in Grok CLI's billing result. The app does not read
/// `auth.json`, copy tokens, or change the CLI login.
struct GrokCLIClient {
    var timeout: TimeInterval = 8

    static func locateExecutable() -> URL? {
        var candidates: [URL] = []
        let home = ProcessInfo.processInfo.environment["GROK_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        candidates.append(home.appendingPathComponent("bin/grok"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/grok"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/grok"))
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("grok"))
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func authFileExists() -> Bool {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        return FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path)
    }

    func fetchBillingPayload() async throws -> Data {
        guard let executable = Self.locateExecutable() else {
            throw GrokCLIError.executableMissing
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = ["agent", "stdio"]
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            let reader = GrokLineCollector(handle: output.fileHandleForReading)
            reader.start()
            errors.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            do {
                try process.run()
            } catch {
                reader.stop()
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: GrokCLIError.executableMissing)
                return
            }

            let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1","clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false},"terminal":false}}}"# + "\n"
            let billingRequest = #"{"jsonrpc":"2.0","id":2,"method":"_x.ai/billing","params":{}}"# + "\n"
            input.fileHandleForWriting.write(Data(initRequest.utf8))
            input.fileHandleForWriting.write(Data(billingRequest.utf8))

            let deadline = Date().addingTimeInterval(timeout)
            let wait = Thread {
                while Date() < deadline {
                    let lines = reader.lines()
                    if GrokCLIProtocol.billingPayload(from: lines) != nil || GrokCLIProtocol.failure(from: lines) != nil,
                       lines.contains(where: { $0.contains("\"id\":2") || $0.contains("\"id\": 2") }) {
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    process.terminate()
                    if process.isRunning {
                        process.interrupt()
                    }
                }
                reader.stop()
                errors.fileHandleForReading.readabilityHandler = nil
                let lines = reader.lines()
                if Date() >= deadline, GrokCLIProtocol.billingPayload(from: lines) == nil, GrokCLIProtocol.failure(from: lines) == nil {
                    continuation.resume(throwing: GrokCLIError.timedOut)
                    return
                }
                if let failure = GrokCLIProtocol.failure(from: lines), GrokCLIProtocol.billingPayload(from: lines) == nil {
                    continuation.resume(throwing: failure == .authenticationRequired ? GrokCLIError.authenticationRequired : GrokCLIError.unavailable)
                    return
                }
                if let payload = GrokCLIProtocol.billingPayload(from: lines) {
                    continuation.resume(returning: payload)
                } else {
                    continuation.resume(throwing: GrokCLIError.unavailable)
                }
            }
            wait.start()
        }
    }
}

enum GrokCLIError: Error {
    case executableMissing
    case authenticationRequired
    case unavailable
    case timedOut
}

private final class GrokLineCollector {
    private let handle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private var collected: [String] = []

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.append(data)
        }
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    func lines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    private func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let text = String(data: line, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                collected.append(text)
            }
        }
        lock.unlock()
    }
}
