import Darwin
import Foundation

/// Reads the signed-in Grok CLI's billing result. The app does not read
/// `auth.json`, copy tokens, or change the CLI login.
nonisolated struct GrokCLIClient {
    var timeout: TimeInterval = 8
    var executable: URL?
    let home: URL

    static func locateExecutable() -> URL? {
        var candidates: [URL] = []
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        if let configured = ProcessInfo.processInfo.environment["GROK_HOME"], configured.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true).appendingPathComponent("bin/grok"))
        }
        candidates.append(userHome.appendingPathComponent(".grok/bin/grok"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/grok"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/grok"))
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("grok"))
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func authFileExists(in home: URL) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path)
    }

    func fetchBillingPayload() async throws -> Data {
        try Task.checkCancellation()
        guard let executable = executable ?? Self.locateExecutable() else { throw GrokCLIError.executableMissing }
        let cancelled = Pipe()
        let result: Result<Data, Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result { try exchange(with: executable, cancelled: cancelled) })
                }
            }
        } onCancel: {
            // Wake the I/O worker. Only that worker owns the child and resumes the continuation.
            try? cancelled.fileHandleForWriting.close()
        }
        try Task.checkCancellation()
        return try result.get()
    }

    private func exchange(with executable: URL, cancelled: Pipe) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let exited = Pipe()
        process.executableURL = executable
        // Each request uses its profile's login, never a shared leader or a process-wide API key.
        var environment = ProcessInfo.processInfo.environment
        environment["GROK_HOME"] = home.path
        environment.removeValue(forKey: "XAI_API_KEY")
        process.environment = environment
        process.arguments = ["agent", "--no-leader", "stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in try? exited.fileHandleForWriting.close() }

        let stdin = input.fileHandleForWriting
        guard fcntl(stdin.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { throw GrokCLIError.unavailable }
        do { try process.run() } catch { throw GrokCLIError.executableMissing }
        let exitFD = exited.fileHandleForReading.fileDescriptor
        defer {
            try? stdin.close()
            if process.isRunning {
                process.terminate()
                // A CLI ignoring SIGTERM must not survive cancellation or the deadline.
                var event = pollfd(fd: exitFD, events: Int16(POLLIN), revents: 0)
                if poll(&event, 1, 250) <= 0, process.isRunning {
                    let pid = process.processIdentifier
                    kill(getpgid(pid) == pid ? -pid : pid, SIGKILL)
                }
            }
            process.waitUntilExit()
        }

        func send(_ request: String) throws {
            do { try stdin.write(contentsOf: Data(request.utf8)) } catch { throw GrokCLIError.unavailable }
        }
        var expectedID = 1
        func receive(_ line: Data) throws -> Data? {
            guard let reply = GrokCLIProtocol.reply(to: expectedID, in: line) else { return nil }
            let payload = try reply.get()
            if expectedID == 2 { return payload }
            expectedID = 2
            try send(#"{"jsonrpc":"2.0","id":2,"method":"_x.ai/billing","params":{}}"# + "\n")
            return nil
        }

        try send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false},"terminal":false}}}"# + "\n")
        let stdout = output.fileHandleForReading
        var events = [stdout.fileDescriptor, cancelled.fileHandleForReading.fileDescriptor, exitFD]
            .map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var bytes = [UInt8](repeating: 0, count: 8192)
        var buffer = Data()
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw GrokCLIError.timedOut }
            // Sleep in the kernel until stdout, child exit, cancellation, or the single deadline.
            let ready = poll(&events, 3, Int32(ceil(remaining * 1000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw GrokCLIError.unavailable }
            guard ready > 0 else { throw GrokCLIError.timedOut }
            guard events[1].revents == 0 else { throw CancellationError() }

            // A child can exit with a complete reply still buffered in stdout.
            let count = events[0].revents == 0 ? 0 : bytes.withUnsafeMutableBytes {
                Darwin.read(stdout.fileDescriptor, $0.baseAddress!, $0.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw GrokCLIError.unavailable }
            guard count > 0 else {
                if !buffer.isEmpty, let payload = try receive(buffer) { return payload }
                throw GrokCLIError.unavailable
            }
            var start = 0
            for i in 0..<count where bytes[i] == 10 {
                buffer.append(contentsOf: bytes[start..<i])
                if let payload = try receive(buffer) { return payload }
                buffer.removeAll(keepingCapacity: true)
                start = i + 1
            }
            buffer.append(contentsOf: bytes[start..<count])
        }
    }
}

enum GrokCLIError: Error {
    case executableMissing
    case authenticationRequired
    case unavailable
    case timedOut
}

