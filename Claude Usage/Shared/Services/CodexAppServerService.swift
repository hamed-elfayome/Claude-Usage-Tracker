import Foundation
import Darwin

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

protocol CodexAppServerTransport: AnyObject {
    var isRunning: Bool { get }
    var onStdout: ((Data) -> Void)? { get set }
    var onStderr: ((Data) -> Void)? { get set }
    var onTermination: (() -> Void)? { get set }

    func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) throws
    func send(_ data: Data) throws
    func stop()
}

private final class ProcessCodexAppServerTransport: CodexAppServerTransport, @unchecked Sendable {
    var onStdout: ((Data) -> Void)?
    var onStderr: ((Data) -> Void)?
    var onTermination: (() -> Void)?

    private var process: Process?
    private var inputHandle: FileHandle?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool { process?.isRunning == true }

    func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.onStdout?(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.onStderr?(data)
        }
        process.terminationHandler = { [weak self] _ in
            self?.onTermination?()
        }

        self.process = process
        self.inputHandle = stdinPipe.fileHandleForWriting
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
        } catch {
            stop()
            throw error
        }
    }

    func send(_ data: Data) throws {
        guard let inputHandle else {
            throw CodexAppServerError.processTerminated
        }
        try inputHandle.write(contentsOf: data)
    }

    func stop() {
        let process = process
        self.process = nil
        let inputHandle = inputHandle
        self.inputHandle = nil

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process?.terminationHandler = nil
        try? inputHandle?.close()

        if let process, process.isRunning {
            let processIdentifier = process.processIdentifier
            process.terminate()

            // SSH or a wedged app-server can ignore SIGTERM. Keep the Process
            // alive long enough to verify termination, then force cleanup so a
            // timed-out/deleted profile cannot leave an orphan behind.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                guard process.isRunning else { return }
                Darwin.kill(processIdentifier, SIGKILL)
            }
        }
    }
}

/// Long-lived JSON-RPC client for `codex app-server --stdio`.
///
/// The service deliberately delegates authentication to Codex. It never reads
/// or copies `~/.codex/auth.json`.
final class CodexAppServerService: @unchecked Sendable {
    static let shared = CodexAppServerService()
    typealias TransportFactory = () -> CodexAppServerTransport

    private struct LaunchSpec: Equatable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]?
        let identity: String
    }

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeout: DispatchWorkItem
    }

    private final class CommandOutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        func load() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private let queue = DispatchQueue(label: "com.claudeusagetracker.codex-app-server")
    private let requestTimeout: TimeInterval
    private let transportFactory: TransportFactory
    private var transport: CodexAppServerTransport?
    private var stdoutBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var initializationTask: Task<Void, Error>?
    private var activeLaunchSpec: LaunchSpec?

    init(
        requestTimeout: TimeInterval = 15,
        transportFactory: TransportFactory? = nil
    ) {
        self.requestTimeout = requestTimeout
        self.transportFactory = transportFactory ?? {
            ProcessCodexAppServerTransport()
        }
    }

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
        try await fetchUsage(
            configuration: CodexProfileConfiguration(executablePath: executablePath)
        )
    }

    func fetchUsage(configuration: CodexProfileConfiguration) async throws -> CodexUsage {
        let launchSpec = try Self.appServerLaunchSpec(for: configuration)
        try await ensureInitialized(launchSpec: launchSpec)

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

    private func ensureInitialized(launchSpec: LaunchSpec) async throws {
        let task: Task<Void, Error> = queue.sync {
            if transport?.isRunning == true, activeLaunchSpec != launchSpec {
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
                try self.startIfNeeded(launchSpec: launchSpec)
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

    private func startIfNeeded(launchSpec: LaunchSpec) throws {
        try queue.sync {
            if transport?.isRunning == true { return }

            let newTransport = transportFactory()
            newTransport.onStdout = { [weak self] data in
                self?.queue.async {
                    self?.consumeStdoutLocked(data)
                }
            }
            newTransport.onStderr = { data in
                guard let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty else { return }
                LoggingService.shared.log("Codex app-server: \(message)")
            }
            newTransport.onTermination = { [weak self, weak newTransport] in
                guard let newTransport else { return }
                self?.queue.async {
                    guard self?.transport === newTransport else { return }
                    self?.stopLocked(error: CodexAppServerError.processTerminated)
                }
            }

            transport = newTransport
            activeLaunchSpec = launchSpec
            stdoutBuffer.removeAll(keepingCapacity: true)
            do {
                try newTransport.start(
                    executable: launchSpec.executable,
                    arguments: launchSpec.arguments,
                    environment: launchSpec.environment
                )
            } catch {
                if transport === newTransport {
                    transport = nil
                    activeLaunchSpec = nil
                }
                newTransport.onStdout = nil
                newTransport.onStderr = nil
                newTransport.onTermination = nil
                newTransport.stop()
                throw CodexAppServerError.processLaunchFailed(error.localizedDescription)
            }
        }
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.transport?.isRunning == true else {
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
                    let error = CodexAppServerError.timedOut(method)
                    pending.continuation.resume(throwing: error)
                    // A process that stopped answering one request is unsafe to
                    // reuse, particularly across a stalled SSH connection.
                    self.stopLocked(error: error)
                }
                self.pending[requestID] = PendingRequest(
                    method: method,
                    continuation: continuation,
                    timeout: timeout
                )
                self.queue.asyncAfter(
                    deadline: .now() + self.requestTimeout,
                    execute: timeout
                )

                do {
                    try self.writeLocked(message)
                } catch {
                    timeout.cancel()
                    self.pending.removeValue(forKey: requestID)
                    let requestError = CodexAppServerError.requestFailed(
                        error.localizedDescription
                    )
                    continuation.resume(throwing: requestError)
                    // A failed stdin write means the transport is no longer
                    // usable even if Process has not observed termination yet.
                    // Fail any sibling requests and force a clean launch next
                    // time instead of repeatedly writing to a broken pipe.
                    self.stopLocked(error: requestError)
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try queue.sync {
            guard transport?.isRunning == true else {
                throw CodexAppServerError.processTerminated
            }
            try writeLocked(["method": method, "params": params])
        }
    }

    private func writeLocked(_ object: [String: Any]) throws {
        guard let transport else {
            throw CodexAppServerError.processTerminated
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try transport.send(data)
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

    private func stopLocked(error: Error) {
        let currentTransport = transport
        transport = nil
        activeLaunchSpec = nil
        initialized = false
        initializationTask = nil
        stdoutBuffer.removeAll(keepingCapacity: false)

        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }

        currentTransport?.onStdout = nil
        currentTransport?.onStderr = nil
        currentTransport?.onTermination = nil
        // Also close pipe handles after an observed termination. The concrete
        // transport only sends a termination signal when its process is still
        // running, so this is safe in both paths.
        currentTransport?.stop()
    }

    static func resolveExecutable(customExecutablePath: String? = nil) -> URL? {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment

        if let customExecutablePath = customExecutablePath?.nilIfBlank {
            return FileManager.default.isExecutableFile(atPath: customExecutablePath)
                ? URL(fileURLWithPath: customExecutablePath)
                : nil
        }
        if let override = environment["CODEX_EXECUTABLE"]?.nilIfBlank {
            return FileManager.default.isExecutableFile(atPath: override)
                ? URL(fileURLWithPath: override)
                : nil
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

    private static func appServerLaunchSpec(
        for configuration: CodexProfileConfiguration
    ) throws -> LaunchSpec {
        if let validationError = configuration.validationError {
            throw CodexAppServerError.processLaunchFailed(validationError)
        }

        switch configuration.connectionType {
        case .local:
            guard let executable = resolveExecutable(
                customExecutablePath: configuration.executablePath
            ) else {
                throw CodexAppServerError.executableNotFound
            }
            var environment = ProcessInfo.processInfo.environment
            if let codexHome = configuration.codexHome {
                environment["CODEX_HOME"] = codexHome
            }
            return LaunchSpec(
                executable: executable,
                arguments: ["app-server", "--stdio"],
                environment: environment,
                identity: "local|\(executable.path)|\(configuration.codexHome ?? "")"
            )

        case .ssh:
            guard let host = configuration.sshHost?.nilIfBlank else {
                throw CodexAppServerError.processLaunchFailed("Enter an SSH host alias.")
            }
            let sshURL = URL(fileURLWithPath: "/usr/bin/ssh")
            guard FileManager.default.isExecutableFile(atPath: sshURL.path) else {
                throw CodexAppServerError.processLaunchFailed("The macOS SSH client was not found.")
            }
            let remoteExecutable = configuration.executablePath ?? "codex"
            let command = remoteCommand(
                executable: remoteExecutable,
                arguments: ["app-server", "--stdio"],
                codexHome: configuration.codexHome
            )
            return LaunchSpec(
                executable: sshURL,
                arguments: sshArguments(host: host, remoteCommand: command),
                environment: nil,
                identity: "ssh|\(host)|\(remoteExecutable)|\(configuration.codexHome ?? "")"
            )
        }
    }

    private static func remoteCommand(
        executable: String,
        arguments: [String],
        codexHome: String?
    ) -> String {
        var parts: [String] = []
        if let codexHome {
            parts += ["env", "CODEX_HOME=\(shellQuote(codexHome))"]
        }
        parts.append(shellQuote(executable))
        parts += arguments.map(shellQuote)
        return parts.joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func sshArguments(host: String, remoteCommand: String) -> [String] {
        [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            host,
            remoteCommand
        ]
    }

    /// Checks the selected CLI without touching Codex credential files. The
    /// stable `codex login status` command reports whether the CLI can reuse an
    /// existing local login.
    static func inspectInstallation(customExecutablePath: String? = nil) async -> CodexInstallationDiagnostics {
        await inspectInstallation(
            configuration: CodexProfileConfiguration(executablePath: customExecutablePath)
        )
    }

    static func inspectInstallation(
        configuration: CodexProfileConfiguration
    ) async -> CodexInstallationDiagnostics {
        return await Task.detached(priority: .utility) {
            let versionSpec: LaunchSpec
            let loginSpec: LaunchSpec
            do {
                versionSpec = try commandLaunchSpec(for: configuration, arguments: ["--version"])
                loginSpec = try commandLaunchSpec(for: configuration, arguments: ["login", "status"])
            } catch {
                return CodexInstallationDiagnostics(
                    executablePath: nil,
                    version: nil,
                    isSignedIn: false,
                    loginStatus: nil,
                    error: error.localizedDescription
                )
            }
            let versionResult = runCommand(spec: versionSpec)
            let loginResult = runCommand(spec: loginSpec)
            return CodexInstallationDiagnostics(
                executablePath: versionResult.status == 0
                    ? (configuration.connectionType == .local
                        ? versionSpec.executable.path
                        : configuration.connectionSummary)
                    : nil,
                version: versionResult.output.isEmpty ? nil : versionResult.output,
                isSignedIn: loginResult.status == 0,
                loginStatus: loginResult.output.isEmpty ? nil : loginResult.output,
                error: versionResult.status == 0 ? nil : versionResult.output
            )
        }.value
    }

    private static func commandLaunchSpec(
        for configuration: CodexProfileConfiguration,
        arguments: [String]
    ) throws -> LaunchSpec {
        if let validationError = configuration.validationError {
            throw CodexAppServerError.processLaunchFailed(validationError)
        }
        switch configuration.connectionType {
        case .local:
            guard let executable = resolveExecutable(customExecutablePath: configuration.executablePath) else {
                throw CodexAppServerError.executableNotFound
            }
            var environment = ProcessInfo.processInfo.environment
            if let codexHome = configuration.codexHome {
                environment["CODEX_HOME"] = codexHome
            }
            return LaunchSpec(
                executable: executable,
                arguments: arguments,
                environment: environment,
                identity: "diagnostic"
            )
        case .ssh:
            guard let host = configuration.sshHost else {
                throw CodexAppServerError.processLaunchFailed("Enter an SSH host alias.")
            }
            let executable = URL(fileURLWithPath: "/usr/bin/ssh")
            let command = remoteCommand(
                executable: configuration.executablePath ?? "codex",
                arguments: arguments,
                codexHome: configuration.codexHome
            )
            return LaunchSpec(
                executable: executable,
                arguments: sshArguments(host: host, remoteCommand: command),
                environment: nil,
                identity: "diagnostic"
            )
        }
    }

    private static func runCommand(spec: LaunchSpec) -> (status: Int32, output: String) {
        let process = Process()
        let outputPipe = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        if let environment = spec.environment {
            process.environment = environment
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return (-1, error.localizedDescription)
        }

        // Drain output concurrently so a verbose command cannot fill the pipe
        // and deadlock before the process exits.
        let output = CommandOutputBox()
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            output.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        let didTimeOut = finished.wait(timeout: .now() + 15) == .timedOut
        if didTimeOut, process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        process.terminationHandler = nil

        if outputGroup.wait(timeout: .now() + 2) == .timedOut {
            try? outputPipe.fileHandleForReading.close()
            _ = outputGroup.wait(timeout: .now() + 1)
        }

        var message = String(data: output.load(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if didTimeOut {
            let timeoutMessage = "Command timed out after 15 seconds"
            message = message.isEmpty ? timeoutMessage : "\(message)\n\(timeoutMessage)"
            return (-2, message)
        }
        return (process.terminationStatus, message)
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
            guard byID.isEmpty || !buckets.isEmpty else {
                throw CodexAppServerError.invalidResponse
            }
        } else if let bucket = rateLimitResult["rateLimits"] as? [String: Any] {
            buckets = bucket.isEmpty ? [] : [bucket]
        } else {
            throw CodexAppServerError.invalidResponse
        }

        let rateLimits = buckets.compactMap(parseRateLimit).sorted {
            if $0.id == "codex" { return true }
            if $1.id == "codex" { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        guard buckets.isEmpty
                || rateLimits.contains(where: { $0.primary != nil || $0.secondary != nil }) else {
            throw CodexAppServerError.invalidResponse
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
