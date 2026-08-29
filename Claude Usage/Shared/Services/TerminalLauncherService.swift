//
//  TerminalLauncherService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-08-29.
//

import Foundation

/// Installs per-profile terminal launcher commands so each Tracker profile can
/// drive its own Claude Code login:
///
///   claude          → default `~/.claude` config dir → the ACTIVE profile
///                     (the app already syncs it on every switch)
///   claude-<slug>   → dedicated `~/.claude-<slug>` config dir → THIS profile,
///                     regardless of which one is active
///
/// The launcher is a tiny script in `~/.local/bin` that exports
/// `CLAUDE_CONFIG_DIR` and execs `claude`. Claude Code keeps one login per
/// config dir (keychain entry `Claude Code-credentials-<SHA256(path)[:8]>`),
/// so the FIRST launcher session needs a one-time `/login`; after that the app
/// detects the new keychain entry and pins the profile to it
/// (`customKeychainServiceName`), which makes usage tracking follow that
/// account without ever rotating its tokens (#290).
///
/// Deliberately NOT done: seeding the profile's cached credentials into the
/// new config dir. That would put one refresh-token lineage in two config
/// dirs — whichever Claude Code instance refreshes second gets invalid_grant
/// and a forced re-login (the exact failure mode #290 eliminated).
class TerminalLauncherService {
    static let shared = TerminalLauncherService()

    private let fileManager: FileManager
    private let homeDirectory: URL

    /// Marker prefix embedded in generated scripts so install/uninstall only
    /// ever touches files this app wrote.
    private static let markerPrefix = "# claude-usage-launcher-profile: "

    init(fileManager: FileManager = .default, homeDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    // MARK: - Paths & Naming

    /// `~/.local/bin` — the XDG-conventional per-user bin dir; needs no sudo.
    var binDirectory: URL {
        homeDirectory.appendingPathComponent(".local/bin")
    }

    /// Lowercased, non-alphanumerics collapsed to single dashes, trimmed.
    /// "My Work Acct!" → "my-work-acct". Falls back to a short id-derived slug
    /// for names with no usable characters.
    func slug(for name: String, profileId: UUID) -> String {
        var out = ""
        var lastWasDash = true  // suppress leading dash
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.isEmpty {
            out = String(profileId.uuidString.prefix(8)).lowercased()
        }
        return out
    }

    func launcherName(forSlug slug: String) -> String { "claude-\(slug)" }

    func scriptURL(forSlug slug: String) -> URL {
        binDirectory.appendingPathComponent(launcherName(forSlug: slug))
    }

    func configDirectory(forSlug slug: String) -> URL {
        homeDirectory.appendingPathComponent(".claude-\(slug)")
    }

    /// The keychain service Claude Code will create for this launcher's config
    /// dir after the user's first `/login` in a launcher session.
    func expectedKeychainService(forSlug slug: String) -> String {
        let path = configDirectory(forSlug: slug).path
        let hash = ClaudeCodeSyncService.shared.sha256HexPrefix(path, length: 8)
        return "Claude Code-credentials-\(hash)"
    }

    // MARK: - Install / Uninstall

    /// A slug not already claimed by another profile's launcher script.
    /// Collisions (two profiles slugging identically) get a short id suffix.
    func availableSlug(for profile: Profile) -> String {
        let base = slug(for: profile.name, profileId: profile.id)
        let url = scriptURL(forSlug: base)
        if let owner = installedProfileId(atScript: url), owner != profile.id {
            return "\(base)-\(String(profile.id.uuidString.prefix(4)).lowercased())"
        }
        return base
    }

    func isInstalled(_ profile: Profile) -> Bool {
        guard let slug = profile.terminalLauncherSlug else { return false }
        return installedProfileId(atScript: scriptURL(forSlug: slug)) == profile.id
    }

    /// Writes the launcher script (0755) and creates the config dir.
    /// Returns the slug that was used (store it on the profile).
    @discardableResult
    func install(for profile: Profile) throws -> String {
        let slug = profile.terminalLauncherSlug ?? availableSlug(for: profile)
        let configDir = configDirectory(forSlug: slug)

        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)

        let script = """
        #!/bin/bash
        \(Self.markerPrefix)\(profile.id.uuidString)
        # Generated by Claude Usage for profile "\(profile.name)".
        # Runs Claude Code with its own config dir so this profile keeps its own
        # login (run /login once in the first session). Safe to delete.
        export CLAUDE_CONFIG_DIR="\(configDir.path)"
        exec claude "$@"

        """
        let url = scriptURL(forSlug: slug)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        LoggingService.shared.log("TerminalLauncher: installed \(launcherName(forSlug: slug)) → \(configDir.path)")
        return slug
    }

    /// Removes the launcher script. The config dir (and its login) is left in
    /// place — deleting a login because the user removed a convenience command
    /// would be data loss; they can delete `~/.claude-<slug>` themselves.
    func uninstall(_ profile: Profile) {
        guard let slug = profile.terminalLauncherSlug else { return }
        let url = scriptURL(forSlug: slug)
        guard installedProfileId(atScript: url) == profile.id else { return }
        try? fileManager.removeItem(at: url)
        LoggingService.shared.log("TerminalLauncher: removed \(launcherName(forSlug: slug))")
    }

    // MARK: - Pinning

    /// True once Claude Code has created the launcher's keychain entry (i.e.
    /// the user has done the one-time `/login` in a launcher session).
    func loginDetected(_ profile: Profile) -> Bool {
        guard let slug = profile.terminalLauncherSlug else { return false }
        let expected = expectedKeychainService(forSlug: slug)
        return ClaudeCodeSyncService.shared.listClaudeCodeKeychainServices().contains(expected)
    }

    /// When the launcher's keychain entry exists and the profile isn't pinned
    /// to it yet, pin it so usage tracking follows this login. Returns true if
    /// the profile was updated.
    func pinIfLoginDetected(_ profile: Profile) -> Bool {
        guard let slug = profile.terminalLauncherSlug else { return false }
        let expected = expectedKeychainService(forSlug: slug)
        guard profile.customKeychainServiceName != expected, loginDetected(profile) else {
            return false
        }
        var updated = profile
        updated.customKeychainServiceName = expected
        updated.hasCliAccount = true
        ProfileManager.shared.updateProfile(updated)
        LoggingService.shared.log("TerminalLauncher: pinned '\(profile.name)' to \(expected)")
        return true
    }

    // MARK: - PATH

    /// Whether `~/.local/bin` is on the user's PATH (checked against the login
    /// shell's environment, not just the app's, which launchd starts bare).
    func isBinDirOnPath() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if path.split(separator: ":").map(String.init).contains(binDirectory.path) {
            return true
        }
        // The app's own PATH is launchd's minimal one; ask the login shell.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning { process.terminate(); return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let shellPath = String(data: data, encoding: .utf8) ?? ""
        return shellPath.split(whereSeparator: { $0 == ":" || $0.isNewline })
            .map(String.init).contains(binDirectory.path)
    }

    /// The line users add to their shell profile when `~/.local/bin` is missing.
    var pathExportLine: String {
        "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    // MARK: - Internals

    /// Profile UUID embedded in a launcher script's marker line, or nil when
    /// the file is absent or wasn't written by this app.
    private func installedProfileId(atScript url: URL) -> UUID? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            if line.hasPrefix(Self.markerPrefix) {
                return UUID(uuidString: String(line.dropFirst(Self.markerPrefix.count)))
            }
        }
        return nil
    }
}
