//
//  AntigravityCLILocator.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  Finds the `agy` (Antigravity CLI) binary. The app is launched by launchd
//  with a minimal PATH, so well-known install locations are checked first and
//  the user's login shell is asked once as a fallback.
//

import Foundation

nonisolated final class AntigravityCLILocator: @unchecked Sendable {
    static let shared = AntigravityCLILocator(warmUpInBackground: true)

    private let environment: [String: String]
    private let candidates: [URL]
    private let isExecutable: (URL) -> Bool
    private let shellLookup: () async -> URL?
    /// When the quick check misses, start the login-shell lookup in the
    /// background, so a refresh after launch finds an `agy` that is only on
    /// the login shell's PATH without anyone opening Settings first.
    private let warmUpInBackground: Bool

    private let lock = NSLock()
    private var shellResolved: URL?
    private var shellLookupDone = false
    private var warmUpStarted = false

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
        shellLookup: (() async -> URL?)? = nil,
        warmUpInBackground: Bool = false
    ) {
        self.environment = environment
        self.candidates = [
            homeDirectory.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy"),
        ]
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup ?? Self.loginShellLookup
        self.warmUpInBackground = warmUpInBackground
    }

    /// Synchronous, cheap: the `AGY_BIN` override, the well-known install
    /// paths, then whatever an earlier `resolve()` found via the login shell.
    /// Safe to call from `hasCredentials` on every refresh.
    func cachedExecutable() -> URL? {
        if let override = environment["AGY_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            if isExecutable(url) { return url }
        }
        if let found = candidates.first(where: isExecutable) { return found }
        lock.lock()
        if let shellResolved, isExecutable(shellResolved) { lock.unlock(); return shellResolved }
        let startWarmUp = warmUpInBackground && !shellLookupDone && !warmUpStarted
        if startWarmUp { warmUpStarted = true }
        lock.unlock()
        if startWarmUp {
            Task.detached(priority: .utility) { [self] in _ = await self.resolve() }
        }
        return nil
    }

    /// `cachedExecutable()`, falling back once to the login shell's `command -v agy`.
    func resolve() async -> URL? {
        if let url = cachedExecutable() { return url }
        if lock.withLock({ shellLookupDone }) { return nil }

        let found = await shellLookup()
        return lock.withLock {
            shellLookupDone = true
            if let found, isExecutable(found) { shellResolved = found }
            return shellResolved
        }
    }

    /// Forget a failed login-shell lookup (e.g. after the user installs `agy`
    /// and presses "Test connection").
    func resetShellLookup() {
        lock.lock(); defer { lock.unlock() }
        shellLookupDone = false
        shellResolved = nil
        warmUpStarted = false
    }

    private static func loginShellLookup() async -> URL? {
        guard let result = try? await AntigravityProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-l", "-c", "command -v agy"],
            timeout: 5
        ), result.exitCode == 0 else { return nil }
        let path = String(decoding: result.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}
