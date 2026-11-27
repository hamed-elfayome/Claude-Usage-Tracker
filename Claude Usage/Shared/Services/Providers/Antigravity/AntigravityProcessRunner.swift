//
//  AntigravityProcessRunner.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  Runs a CLI with a hard deadline. One worker thread owns the child: it
//  sleeps in `poll()` on stdout, stderr and an exit pipe, reads with plain
//  `read()` (no FileHandle readability handlers, whose late callbacks race the
//  termination handler and can raise ObjC exceptions), and stops the child
//  early when the output already answers the question. Lessons from #179:
//  every subprocess is bounded, and a child that ignores SIGTERM gets SIGKILL.
//  The poll loop follows the Grok CLI client in #368; a shared runner could
//  serve both once that lands.
//

import Foundation

/// What a finished (or stopped) process produced.
nonisolated struct AntigravityProcessResult: Sendable {
    /// Exit status, or `nil` when the process was killed by a signal.
    let exitCode: Int32?
    let stdout: Data
    let stderr: Data
    /// The deadline passed and the process had to be stopped.
    let timedOut: Bool
    /// `stopWhen` matched and the process was stopped on purpose.
    let stoppedEarly: Bool
}

/// Markers in agy's output. `nonisolated` because the runner's stop check
/// evaluates it on its worker thread.
nonisolated enum AntigravityOutputMarkers {
    static let authRequired = "Authentication required"

    static func containsAuthRequired(_ stderr: Data) -> Bool {
        String(decoding: stderr, as: UTF8.self).contains(authRequired)
    }
}

nonisolated enum AntigravityProcessRunner {

    enum RunError: Error, Equatable {
        /// The executable could not be launched at all.
        case launchFailed(String)
        /// `poll()` failed unexpectedly.
        case ioFailed(Int32)
    }

    /// After the child exits, how long to keep reading pipes a grandchild
    /// might still hold open before giving up on them.
    static let drainGrace: TimeInterval = 0.5

    /// Runs `executable` and returns once its output is complete, the
    /// deadline passes, or `stopWhen` matches the output read so far.
    ///
    /// - Parameters:
    ///   - stopWhen: evaluated after every chunk of output; returning `true`
    ///     stops the process (e.g. a CLI that prints a login prompt and then
    ///     waits for a browser).
    ///   - maxOutputBytes: per stream; output beyond this is read and dropped.
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval,
        maxOutputBytes: Int = 4 * 1024 * 1024,
        stopWhen: (@Sendable (_ stdout: Data, _ stderr: Data) -> Bool)? = nil
    ) async throws -> AntigravityProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try runBlocking(executable: executable, arguments: arguments, environment: environment,
                                    currentDirectory: currentDirectory, timeout: timeout,
                                    maxOutputBytes: maxOutputBytes, stopWhen: stopWhen)
                })
            }
        }
    }

    private static func runBlocking(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        currentDirectory: URL?,
        timeout: TimeInterval,
        maxOutputBytes: Int,
        stopWhen: (@Sendable (Data, Data) -> Bool)?
    ) throws -> AntigravityProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        let exitPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Closing the write end makes the exit pipe readable (EOF) the moment
        // the child exits, so poll() wakes for it like for output.
        process.terminationHandler = { _ in try? exitPipe.fileHandleForWriting.close() }

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        let exitFD = exitPipe.fileHandleForReading.fileDescriptor

        var stdout = Data()
        var stderr = Data()
        var timedOut = false
        var stoppedEarly = false
        var exitedAt: TimeInterval?

        // A negative fd is ignored by poll(): that is how a stream is retired.
        var fds = [outFD, errFD, exitFD].map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        loop: while fds[0].fd >= 0 || fds[1].fd >= 0 {
            let now = ProcessInfo.processInfo.systemUptime
            var limit = deadline
            if let exitedAt { limit = min(limit, exitedAt + drainGrace) }
            let remaining = limit - now
            if remaining <= 0 {
                if exitedAt == nil { timedOut = true }
                break
            }

            let ready = poll(&fds, nfds_t(fds.count), Int32(ceil(remaining * 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                let code = errno
                stop(process, exitFD: exitFD)
                process.waitUntilExit()
                throw RunError.ioFailed(code)
            }
            if ready == 0 { continue }  // the next pass sees the limit

            for index in 0..<2 where fds[index].fd >= 0 && fds[index].revents != 0 {
                let fd = fds[index].fd
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                if count <= 0 {
                    fds[index].fd = -1  // EOF (or a read error): this stream is done
                    continue
                }
                let room = maxOutputBytes - (index == 0 ? stdout.count : stderr.count)
                if room > 0 {
                    let chunk = buffer[0..<min(count, room)]
                    if index == 0 { stdout.append(contentsOf: chunk) } else { stderr.append(contentsOf: chunk) }
                }
                if let stopWhen, stopWhen(stdout, stderr) {
                    stoppedEarly = true
                    break loop
                }
            }

            if fds[2].fd >= 0 && fds[2].revents != 0 {
                fds[2].fd = -1
                exitedAt = ProcessInfo.processInfo.systemUptime
            }
        }

        stop(process, exitFD: exitFD)
        process.waitUntilExit()
        // Pipes are closed when their FileHandles are released, after this returns.
        let exitCode: Int32? = process.terminationReason == .exit ? process.terminationStatus : nil
        return AntigravityProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr,
                                        timedOut: timedOut, stoppedEarly: stoppedEarly)
    }

    /// SIGTERM, then SIGKILL if the child is still alive 0.5 s later.
    private static func stop(_ process: Process, exitFD: Int32) {
        guard process.isRunning else { return }
        process.terminate()
        var event = pollfd(fd: exitFD, events: Int16(POLLIN), revents: 0)
        if poll(&event, 1, 500) <= 0, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
