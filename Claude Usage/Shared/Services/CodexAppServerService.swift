import Foundation

enum CodexAppServerError: LocalizedError {
    case executableNotFound
    case processLaunchFailed(String)
    case processTerminated
    case invalidResponse
    case requestFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Codex CLI was not found"
        case .processLaunchFailed(let message):
            return "Codex app-server could not start: \(message)"
        case .processTerminated:
            return "Codex app-server stopped unexpectedly"
        case .invalidResponse:
            return "Codex app-server returned an invalid response"
        case .requestFailed(let message):
            return "Codex app-server request failed: \(message)"
        case .timedOut(let method):
            return "Codex app-server request timed out: \(method)"
        }
    }
}

/// Long-lived JSON-RPC client for `codex app-server --stdio`.
///
/// The service deliberately delegates authentication to Codex. It never reads
/// or copies `~/.codex/auth.json`.
final class CodexAppServerService: @unchecked Sendable {
    static let shared = CodexAppServerService()

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeout: DispatchWorkItem
    }

    private let queue = DispatchQueue(label: "com.claudeusagetracker.codex-app-server")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var initializationTask: Task<Void, Error>?
    private var activeExecutableURL: URL?

    private init() {}

    deinit {
        stop()
    }

    var isAvailable: Bool {
        isAvailable(customExecutablePath: nil)
    }

    func isAvailable(customExecutablePath: String?) -> Bool {
        Self.resolveExecutable(customExecutablePath: customExecutablePath) != nil
    }

    func fetchUsage(executablePath: String? = nil) async throws -> CodexUsage {
        guard let executable = Self.resolveExecutable(customExecutablePath: executablePath) else {
            throw CodexAppServerError.executableNotFound
        }
        try await ensureInitialized(executable: executable)

        // Rate limits are the core feature. Account metadata and lifetime token
        // summaries were added later and should not make the tray fail against
        // an older Codex installation or an account that omits those surfaces.
        async let accountResult = optionalRequest(
            method: "account/read",
            params: ["refreshToken": false]
        )
        async let tokenUsageResult = optionalRequest(method: "account/usage/read", params: nil)
        let rateLimitJSON = try await request(method: "account/rateLimits/read", params: nil)
        let accountJSON = await accountResult ?? [:]
        let tokenUsageJSON = await tokenUsageResult ?? [:]

        return try Self.parseUsage(
            accountResult: accountJSON,
            rateLimitResult: rateLimitJSON,
            tokenUsageResult: tokenUsageJSON
        )
    }

    private func optionalRequest(method: String, params: [String: Any]?) async -> [String: Any]? {
        do {
            return try await request(method: method, params: params)
        } catch {
            LoggingService.shared.log("Codex app-server optional request \(method) failed: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {
        queue.sync {
            stopLocked(error: CodexAppServerError.processTerminated)
        }
    }

    private func ensureInitialized(executable: URL) async throws {
        let task: Task<Void, Error> = queue.sync {
            if process?.isRunning == true, activeExecutableURL != executable {
                stopLocked(error: CodexAppServerError.processTerminated)
            }
            if initialized {
                return Task {}
            }
            if let initializationTask {
                return initializationTask
            }

            let task = Task { [weak self] in
                guard let self else { throw CodexAppServerError.processTerminated }
                try self.startIfNeeded(executable: executable)
                _ = try await self.request(
                    method: "initialize",
                    params: [
                        "clientInfo": [
                            "name": "claude-usage-tracker",
                            "title": "Claude Usage Tracker",
                            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                        ],
                        "capabilities": [:]
                    ]
                )
                try self.sendNotification(method: "initialized", params: [:])
                self.queue.sync {
                    self.initialized = true
                    self.initializationTask = nil
                }
            }
            initializationTask = task
            return task
        }

        do {
            try await task.value
        } catch {
            queue.sync {
                initializationTask = nil
                stopLocked(error: error)
            }
            throw error
        }
    }

    private func startIfNeeded(executable: URL) throws {
        try queue.sync {
            if process?.isRunning == true { return }

            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executable
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.queue.async {
                    self?.consumeStdoutLocked(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty else { return }
                LoggingService.shared.log("Codex app-server: \(message)")
            }
            process.terminationHandler = { [weak self] _ in
                self?.queue.async {
                    self?.stopLocked(error: CodexAppServerError.processTerminated, terminateProcess: false)
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                throw CodexAppServerError.processLaunchFailed(error.localizedDescription)
            }

            self.process = process
            self.activeExecutableURL = executable
            self.stdinHandle = stdinPipe.fileHandleForWriting
            self.stdoutBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.process?.isRunning == true, let stdinHandle = self.stdinHandle else {
                    continuation.resume(throwing: CodexAppServerError.processTerminated)
                    return
                }

                let requestID = self.nextRequestID
                self.nextRequestID += 1

                var message: [String: Any] = ["id": requestID, "method": method]
                if let params {
                    message["params"] = params
                }

                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, let pending = self.pending.removeValue(forKey: requestID) else { return }
                    pending.continuation.resume(throwing: CodexAppServerError.timedOut(method))
                }
                self.pending[requestID] = PendingRequest(
                    method: method,
                    continuation: continuation,
                    timeout: timeout
                )
                self.queue.asyncAfter(deadline: .now() + 15, execute: timeout)

                do {
                    try self.writeLocked(message, to: stdinHandle)
                } catch {
                    timeout.cancel()
                    self.pending.removeValue(forKey: requestID)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try queue.sync {
            guard let stdinHandle else { throw CodexAppServerError.processTerminated }
            try writeLocked(["method": method, "params": params], to: stdinHandle)
        }
    }

    private func writeLocked(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func consumeStdoutLocked(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let requestID = (object["id"] as? NSNumber)?.intValue,
                  let pendingRequest = pending.removeValue(forKey: requestID) else {
                continue
            }

            pendingRequest.timeout.cancel()
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                pendingRequest.continuation.resume(throwing: CodexAppServerError.requestFailed(message))
            } else if let result = object["result"] as? [String: Any] {
                pendingRequest.continuation.resume(returning: result)
            } else {
                pendingRequest.continuation.resume(throwing: CodexAppServerError.invalidResponse)
            }
        }
    }

    private func stopLocked(error: Error, terminateProcess: Bool = true) {
        let currentProcess = process
        process = nil
        activeExecutableURL = nil
        stdinHandle = nil
        initialized = false
        initializationTask = nil
        stdoutBuffer.removeAll(keepingCapacity: false)

        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }

        if terminateProcess, currentProcess?.isRunning == true {
            currentProcess?.terminate()
        }
    }

    static func resolveExecutable(customExecutablePath: String? = nil) -> URL? {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment

        if let customExecutablePath, !customExecutablePath.isEmpty {
            candidates.append(customExecutablePath)
        }
        if let override = environment["CODEX_EXECUTABLE"], !override.isEmpty {
            candidates.append(override)
        }
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Checks the selected CLI without touching Codex credential files. The
    /// stable `codex login status` command reports whether the CLI can reuse an
    /// existing local login.
    static func inspectInstallation(customExecutablePath: String? = nil) async -> CodexInstallationDiagnostics {
        guard let executable = resolveExecutable(customExecutablePath: customExecutablePath) else {
            return CodexInstallationDiagnostics(
                executablePath: nil,
                version: nil,
                isSignedIn: false,
                loginStatus: nil,
                error: CodexAppServerError.executableNotFound.localizedDescription
            )
        }

        return await Task.detached(priority: .utility) {
            let versionResult = runCommand(executable: executable, arguments: ["--version"])
            let loginResult = runCommand(executable: executable, arguments: ["login", "status"])
            return CodexInstallationDiagnostics(
                executablePath: executable.path,
                version: versionResult.output.isEmpty ? nil : versionResult.output,
                isSignedIn: loginResult.status == 0,
                loginStatus: loginResult.output.isEmpty ? nil : loginResult.output,
                error: versionResult.status == 0 ? nil : versionResult.output
            )
        }.value
    }

    private static func runCommand(executable: URL, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    static func parseUsage(
        accountResult: [String: Any],
        rateLimitResult: [String: Any],
        tokenUsageResult: [String: Any]
    ) throws -> CodexUsage {
        let accountObject = accountResult["account"] as? [String: Any]
        let account = accountObject.map {
            CodexAccount(email: $0["email"] as? String, planType: $0["planType"] as? String)
        }

        var buckets: [[String: Any]] = []
        if let byID = rateLimitResult["rateLimitsByLimitId"] as? [String: Any] {
            buckets = byID.compactMap { key, value in
                guard var bucket = value as? [String: Any] else { return nil }
                if bucket["limitId"] == nil { bucket["limitId"] = key }
                return bucket
            }
        } else if let bucket = rateLimitResult["rateLimits"] as? [String: Any] {
            buckets = [bucket]
        }

        let rateLimits = buckets.compactMap(parseRateLimit).sorted {
            if $0.id == "codex" { return true }
            if $1.id == "codex" { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        let summary = tokenUsageResult["summary"] as? [String: Any]
        let daily = (tokenUsageResult["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> CodexDailyTokenUsage? in
            guard let date = bucket["startDate"] as? String,
                  let tokens = (bucket["tokens"] as? NSNumber)?.int64Value else { return nil }
            return CodexDailyTokenUsage(startDate: date, tokens: tokens)
        }
        let tokenUsage = summary.map {
            CodexTokenUsage(
                lifetimeTokens: ($0["lifetimeTokens"] as? NSNumber)?.int64Value,
                peakDailyTokens: ($0["peakDailyTokens"] as? NSNumber)?.int64Value,
                longestRunningTurnSeconds: ($0["longestRunningTurnSec"] as? NSNumber)?.int64Value,
                currentStreakDays: ($0["currentStreakDays"] as? NSNumber)?.int64Value,
                longestStreakDays: ($0["longestStreakDays"] as? NSNumber)?.int64Value,
                dailyBuckets: daily
            )
        }

        return CodexUsage(
            account: account,
            rateLimits: rateLimits,
            tokenUsage: tokenUsage,
            lastUpdated: Date()
        )
    }

    private static func parseRateLimit(_ object: [String: Any]) -> CodexRateLimit? {
        guard let id = object["limitId"] as? String else { return nil }
        return CodexRateLimit(
            id: id,
            name: object["limitName"] as? String,
            primary: parseWindow(object["primary"] as? [String: Any]),
            secondary: parseWindow(object["secondary"] as? [String: Any]),
            credits: parseCredits(object["credits"] as? [String: Any]),
            planType: object["planType"] as? String,
            reachedType: object["rateLimitReachedType"] as? String
        )
    }

    private static func parseWindow(_ object: [String: Any]?) -> CodexRateLimitWindow? {
        guard let object,
              let usedPercent = (object["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
        let reset: Date?
        if let resetSeconds = (object["resetsAt"] as? NSNumber)?.doubleValue {
            reset = Date(timeIntervalSince1970: resetSeconds)
        } else {
            reset = nil
        }
        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: (object["windowDurationMins"] as? NSNumber)?.intValue,
            resetsAt: reset
        )
    }

    private static func parseCredits(_ object: [String: Any]?) -> CodexCredits? {
        guard let object,
              let hasCredits = object["hasCredits"] as? Bool,
              let unlimited = object["unlimited"] as? Bool else { return nil }
        return CodexCredits(
            hasCredits: hasCredits,
            unlimited: unlimited,
            balance: object["balance"] as? String
        )
    }
}
