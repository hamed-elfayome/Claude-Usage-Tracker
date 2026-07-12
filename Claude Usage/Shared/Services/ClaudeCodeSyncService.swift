//
//  ClaudeCodeSyncService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation
import Security
import CryptoKit

/// Manages synchronization of Claude Code CLI credentials between system Keychain and profiles
class ClaudeCodeSyncService {
    static let shared = ClaudeCodeSyncService()

    /// Cached resolved keychain service name (in-memory, cleared per app session)
    private var resolvedServiceName: String?

    /// UserDefaults key for persisting the last successfully resolved hashed service name
    /// so we don't re-run the expensive `security dump-keychain` on every launch.
    private static let persistedServiceNameKey = "ClaudeCodeSyncService.resolvedServiceName"

    /// UserDefaults key marking that hashed-name discovery has already been attempted
    /// once on this machine. When set, we avoid `security dump-keychain` on launch.
    private static let discoveryAttemptedKey = "ClaudeCodeSyncService.discoveryAttempted"

    /// Timeout for blocking `/usr/bin/security` invocations. macOS 26.3.x has been
    /// observed to hang indefinitely on `security` subprocesses in some environments
    /// (see issue #179), so every shell-out is bounded to avoid deadlocking launch.
    private static let securityCommandTimeout: TimeInterval = 3.0

    private init() {}

    // MARK: - Cached Availability Check

    /// Cached result of the "are usable system CLI credentials present?" check.
    /// Keychain access is a blocking XPC round-trip, and UI render paths
    /// (updateAllButtons, popover gating) ask this on every repaint.
    private var systemCredsUsableCache: (value: Bool, checkedAt: Date)?
    private static let systemCredsCacheMaxAge: TimeInterval = 15

    /// Returns whether the system keychain/credentials file holds a
    /// non-expired CLI token, caching the answer briefly so hot render
    /// paths don't hit the keychain on every call.
    func hasUsableSystemCredentials() -> Bool {
        if let cached = systemCredsUsableCache,
           Date().timeIntervalSince(cached.checkedAt) < Self.systemCredsCacheMaxAge {
            return cached.value
        }

        var usable = false
        do {
            if let creds = try readSystemCredentials(),
               !isTokenExpired(creds),
               extractAccessToken(from: creds) != nil {
                usable = true
            }
        } catch {
            LoggingService.shared.log("hasUsableSystemCredentials: system keychain check failed: \(error.localizedDescription)")
        }

        systemCredsUsableCache = (usable, Date())
        return usable
    }

    /// Drops the cached availability answer (call after syncs/logins that
    /// change the keychain state).
    func invalidateSystemCredentialsCache() {
        systemCredsUsableCache = nil
    }

    // MARK: - System Credentials Access (Fallback Chain)

    /// Reads Claude Code credentials using a fallback chain:
    /// 1. ~/.claude/.credentials.json (always complete, not subject to keychain truncation)
    /// 2. System Keychain (may be truncated for large payloads >2KB)
    /// 3. Regex extraction of accessToken from truncated keychain data (last resort)
    func readSystemCredentials() throws -> String? {
        // Read BOTH sources and pick the fresher one. On macOS Claude Code rotates
        // tokens in the KEYCHAIN only; `.credentials.json` is a mirror written by this
        // app at apply-time and goes stale as soon as Claude Code rotates. Letting the
        // file shadow the keychain made sync capture pre-rotation (consumed) tokens,
        // which later failed refresh with invalid_grant and forced re-login.
        let fileJSON = readCredentialsFile()

        // Keychain: validate JSON; fall back to regex extraction for truncated payloads.
        // A keychain read error is fatal only when there is no file to fall back to.
        var keychainJSON: String?
        let rawKeychain: String?
        do {
            rawKeychain = try readKeychainCredentials()
        } catch {
            if fileJSON == nil { throw error }
            rawKeychain = nil
        }
        if let rawJSON = rawKeychain {
            if let data = rawJSON.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil {
                keychainJSON = rawJSON
            } else {
                LoggingService.shared.log("Keychain JSON is invalid (likely truncated), attempting regex extraction")
                if let token = extractAccessTokenViaRegex(from: rawJSON) {
                    keychainJSON = "{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}"
                    LoggingService.shared.log("Built minimal credentials from regex-extracted token")
                } else if fileJSON == nil {
                    // Keychain garbage and no file — surface the error as before.
                    throw ClaudeCodeError.invalidJSON
                }
            }
        }

        switch (fileJSON, keychainJSON) {
        case (nil, nil):
            return nil
        case (let file?, nil):
            LoggingService.shared.log("Read credentials from .credentials.json file (no keychain entry)")
            return file
        case (nil, let keychain?):
            LoggingService.shared.log("Read credentials from keychain (no credentials file)")
            return keychain
        case (let file?, let keychain?):
            // Prefer whichever expires LATER; on a tie (or missing expiry on the file
            // side) prefer the keychain — it is Claude Code's authoritative store.
            let fileExpiry = extractTokenExpiry(from: file)
            let keychainExpiry = extractTokenExpiry(from: keychain)
            if let fe = fileExpiry, let ke = keychainExpiry, fe > ke {
                LoggingService.shared.log("Read credentials from .credentials.json file (newer than keychain)")
                return file
            }
            if keychainExpiry == nil && fileExpiry != nil {
                LoggingService.shared.log("Read credentials from .credentials.json file (keychain entry has no expiry)")
                return file
            }
            LoggingService.shared.log("Read credentials from keychain (authoritative/fresher source)")
            return keychain
        }
    }

    // MARK: - Private Credential Sources

    /// Reads credentials from ~/.claude/.credentials.json or ~/.claude/credentials.json file
    private func readCredentialsFile() -> String? {
        let paths = [
            Constants.ClaudePaths.claudeDirectory.appendingPathComponent(".credentials.json"),
            Constants.ClaudePaths.claudeDirectory.appendingPathComponent("credentials.json")
        ]

        for fileURL in paths {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            guard let data = try? Data(contentsOf: fileURL),
                  let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !jsonString.isEmpty else {
                LoggingService.shared.log("credentials file exists but could not be read: \(fileURL.lastPathComponent)")
                continue
            }

            // Validate it's actually valid JSON
            guard let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                LoggingService.shared.log("credentials file contains invalid JSON: \(fileURL.lastPathComponent)")
                continue
            }

            LoggingService.shared.log("Read credentials from \(fileURL.lastPathComponent)")
            return jsonString
        }

        return nil
    }

    /// Result of a bounded `/usr/bin/security` invocation.
    private struct SecurityCommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    /// Runs `/usr/bin/security` with the given arguments and a hard timeout.
    /// If the timeout elapses, the subprocess is terminated and `timedOut` is true.
    /// This is critical: without the timeout, a hung `security` call blocks the
    /// calling thread (and, if called from main, the whole app) indefinitely.
    private func runSecurityCommand(
        arguments: [String],
        timeout: TimeInterval = ClaudeCodeSyncService.securityCommandTimeout
    ) -> SecurityCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            LoggingService.shared.log("runSecurityCommand: failed to launch security: \(error.localizedDescription)")
            return nil
        }

        // Wait for the process with a hard deadline. DispatchGroup lets us block
        // the current thread up to `timeout` seconds, then terminate if still running.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            LoggingService.shared.log("runSecurityCommand: TIMEOUT after \(timeout)s, terminating security subprocess (args: \(arguments.prefix(2).joined(separator: " ")))")
            process.terminate()
            // Give it a brief moment to die, then force-kill if needed
            _ = group.wait(timeout: .now() + 0.5)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return SecurityCommandResult(exitCode: -1, stdout: "", stderr: "timeout", timedOut: true)
        }

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return SecurityCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: false
        )
    }

    /// Reads Claude Code credentials from system Keychain using security command
    private func readKeychainCredentials() throws -> String? {
        let serviceName = resolveServiceName()
        guard let result = runSecurityCommand(arguments: [
            "find-generic-password",
            "-s", serviceName,
            "-a", NSUserName(),
            "-w"  // Print password only
        ]) else {
            // Failed to launch security — treat as "no credentials"
            return nil
        }

        if result.timedOut {
            LoggingService.shared.log("readKeychainCredentials: security command timed out")
            return nil
        }

        let exitCode = result.exitCode

        if exitCode == 0 {
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } else if exitCode == 44 {
            // Exit code 44 = item not found
            return nil
        } else {
            LoggingService.shared.log("Failed to read keychain: \(result.stderr)")
            throw ClaudeCodeError.keychainReadFailed(status: OSStatus(exitCode))
        }
    }

    /// Extracts accessToken from potentially truncated JSON using regex
    private func extractAccessTokenViaRegex(from rawString: String) -> String? {
        let pattern = "\"accessToken\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawString, range: NSRange(rawString.startIndex..., in: rawString)),
              let tokenRange = Range(match.range(at: 1), in: rawString) else {
            return nil
        }
        return String(rawString[tokenRange])
    }

    // MARK: - Keychain Service Name Discovery

    private static let legacyServiceName = "Claude Code-credentials"

    /// Resolves the correct keychain service name for Claude Code credentials.
    /// Claude Code v2.1.52+ changed from "Claude Code-credentials" to
    /// "Claude Code-credentials-HASH".
    ///
    /// Resolution order (each step is bounded by `securityCommandTimeout`):
    /// 1. In-memory cache
    /// 2. UserDefaults-persisted name from a previous successful resolution
    /// 3. Legacy name probe (`find-generic-password`)
    /// 4. Hashed-name discovery (`dump-keychain`) — only if discovery has not
    ///    been attempted before OR the caller explicitly forced a retry
    ///
    /// Important: `security dump-keychain` is the call most prone to hanging
    /// on macOS 26.3.x (see #179), so we persist a "discovery attempted" flag
    /// and never re-run it on subsequent launches unless the cache is invalidated.
    private func resolveServiceName() -> String {
        if let cached = resolvedServiceName {
            return cached
        }

        // Honor any previously persisted resolution — this avoids the expensive
        // `dump-keychain` shell-out on every launch after the first.
        if let persisted = UserDefaults.standard.string(forKey: Self.persistedServiceNameKey),
           !persisted.isEmpty {
            resolvedServiceName = persisted
            return persisted
        }

        // Try legacy name first (fast path, bounded by timeout)
        if keychainItemExists(serviceName: Self.legacyServiceName) {
            persistResolvedServiceName(Self.legacyServiceName)
            return Self.legacyServiceName
        }

        // Only run the (potentially slow/hanging) hashed-name discovery ONCE
        // per machine. If we've already tried and failed, default to the legacy
        // name and let downstream callers handle the "no credentials" case.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.discoveryAttemptedKey) {
            resolvedServiceName = Self.legacyServiceName
            return Self.legacyServiceName
        }

        // First-time discovery attempt — mark as attempted BEFORE running so that
        // even if the command hangs and gets force-terminated by the timeout,
        // we won't retry it on the next launch.
        defaults.set(true, forKey: Self.discoveryAttemptedKey)

        if let hashedName = findHashedServiceName() {
            persistResolvedServiceName(hashedName)
            LoggingService.shared.log("Resolved hashed keychain service name: \(hashedName)")
            return hashedName
        }

        // Default to legacy name (will fail gracefully if not found)
        resolvedServiceName = Self.legacyServiceName
        return Self.legacyServiceName
    }

    /// Persists a successfully resolved service name to UserDefaults and in-memory cache.
    private func persistResolvedServiceName(_ name: String) {
        resolvedServiceName = name
        UserDefaults.standard.set(name, forKey: Self.persistedServiceNameKey)
    }

    /// Checks if a keychain item exists with the given service name, bounded by
    /// `securityCommandTimeout` so a hung `security` process can't block the caller.
    private func keychainItemExists(serviceName: String) -> Bool {
        guard let result = runSecurityCommand(arguments: [
            "find-generic-password", "-s", serviceName, "-a", NSUserName()
        ]) else {
            return false
        }
        if result.timedOut {
            LoggingService.shared.log("keychainItemExists: security command timed out for service '\(serviceName)'")
            return false
        }
        return result.exitCode == 0
    }

    /// Human-readable summary of a keychain entry, used to label the picker so the user
    /// doesn't have to memorize raw hashes.
    struct KeychainEntryDescription {
        let serviceName: String
        let emailAddress: String?
        let organizationName: String?
        let subscriptionType: String?

        /// Picker label combining the most identifying info available with the
        /// keychain svc shorthand so two similarly-described accounts stay distinct.
        var displayLabel: String {
            let svcShort: String
            if serviceName == "Claude Code-credentials" {
                svcShort = "default"
            } else if serviceName.hasPrefix("Claude Code-credentials-") {
                svcShort = String(serviceName.dropFirst("Claude Code-credentials-".count))
            } else {
                svcShort = serviceName
            }

            if let email = emailAddress {
                if let org = organizationName, !org.isEmpty {
                    return "\(email) — \(org) · \(svcShort)"
                }
                return "\(email) · \(svcShort)"
            }
            if let sub = subscriptionType, !sub.isEmpty {
                return "\(svcShort) — \(sub)"
            }
            return serviceName
        }
    }

    /// Builds a `KeychainEntryDescription` for the given service name. Tries to enrich
    /// the raw hash with human-readable info by:
    /// 1. Reading the keychain payload for `subscriptionType` + `organizationUuid`
    /// 2. Matching that organizationUuid against any of `knownProfiles`' `oauthAccountJSON`
    ///    to recover `emailAddress` + `organizationName`
    /// 3. If still unknown, consulting `accountMap` (built once via
    ///    `discoverAccountLabels()`) which derives hashes from local `.claude*` dirs.
    /// Returns a description that always at least falls back to a sensible svc shorthand.
    func describeKeychainEntry(
        serviceName: String,
        knownProfiles: [Profile],
        accountMap: [String: (email: String, organizationName: String?)] = [:]
    ) -> KeychainEntryDescription {
        var subscription: String?
        var orgUuid: String?

        if let payload = readKeychainCredentials(serviceName: serviceName),
           let data = payload.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
            subscription = oauth["subscriptionType"] as? String
            orgUuid = (root["organizationUuid"] as? String) ?? (oauth["organizationUuid"] as? String)
        }

        var email: String?
        var orgName: String?
        if let orgUuid = orgUuid {
            for profile in knownProfiles {
                guard let json = profile.oauthAccountJSON,
                      let d = json.data(using: .utf8),
                      let r = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      (r["organizationUuid"] as? String) == orgUuid else {
                    continue
                }
                email = r["emailAddress"] as? String
                orgName = r["organizationName"] as? String
                break
            }
        }

        // Fall back to the path-derived account map (covers entries whose keychain
        // payload doesn't carry an organizationUuid — newer Claude Code schemas).
        if email == nil, let mapped = accountMap[serviceName] {
            email = mapped.email
            orgName = mapped.organizationName
        }

        return KeychainEntryDescription(
            serviceName: serviceName,
            emailAddress: email,
            organizationName: orgName,
            subscriptionType: subscription
        )
    }

    /// Discovers a `keychain-svc → (email, org)` mapping by walking the user's home
    /// directory for `.claude` and `.claude-*` config dirs, reading each one's
    /// `.claude.json` `oauthAccount`, and computing the keychain hash Claude Code
    /// derives from each directory path.
    ///
    /// Reverse-engineered fact (validated against live entries): for any non-default
    /// CLAUDE_CONFIG_DIR, Claude Code stores credentials under
    /// `Claude Code-credentials-<SHA256(absolute path)[:8]>`. The default `~/.claude`
    /// maps to the unsuffixed `Claude Code-credentials` entry.
    ///
    /// This is the best path-independent way to label a keychain entry when its
    /// payload doesn't include an organizationUuid (no token data is ever read here —
    /// only `.claude.json` `oauthAccount` metadata, which is plain user identity info).
    func discoverAccountLabels() -> [String: (email: String, organizationName: String?)] {
        var labels: [String: (email: String, organizationName: String?)] = [:]
        let fm = FileManager.default
        let homeURL = fm.homeDirectoryForCurrentUser
        let homePath = homeURL.path

        var candidates: [String] = ["\(homePath)/.claude"]
        if let entries = try? fm.contentsOfDirectory(atPath: homePath) {
            for name in entries where name.hasPrefix(".claude-") {
                candidates.append("\(homePath)/\(name)")
            }
        }

        for dir in candidates {
            let configFile = "\(dir)/.claude.json"
            guard fm.fileExists(atPath: configFile),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oa = root["oauthAccount"] as? [String: Any],
                  let email = oa["emailAddress"] as? String else {
                continue
            }
            let orgName = oa["organizationName"] as? String

            let svc: String
            if dir == "\(homePath)/.claude" {
                svc = "Claude Code-credentials"
            } else {
                let hash = sha256HexPrefix(dir, length: 8)
                svc = "Claude Code-credentials-\(hash)"
            }
            labels[svc] = (email, orgName)
        }
        return labels
    }

    // internal (not private) so unit tests can pin the live-validated hash algorithm.
    func sha256HexPrefix(_ s: String, length: Int) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(length))
    }

    /// Enumerates every Claude Code credentials keychain item — both the legacy
    /// unsuffixed `Claude Code-credentials` entry and all hash-suffix variants
    /// (`Claude Code-credentials-<HASH>`). Used by the Advanced settings UI so the
    /// user can pick the exact entry to pin a profile to.
    ///
    /// Uses `SecItemCopyMatching` (Security.framework) instead of shelling out to
    /// `security dump-keychain` — the shell tool requires broad keychain-access
    /// authorization and on macOS 26.x has been observed to hang indefinitely when
    /// invoked from a background-app context where the keychain prompt cannot be
    /// presented. The Security API is fast, doesn't spawn a subprocess, and only
    /// returns attributes for items the app is already entitled to read.
    func listClaudeCodeKeychainServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                LoggingService.shared.log("listClaudeCodeKeychainServices: SecItemCopyMatching failed (status=\(status))")
            }
            return []
        }
        guard let items = result as? [[String: Any]] else { return [] }

        let prefix = "Claude Code-credentials"
        var found: Set<String> = []
        for item in items {
            guard let name = item[kSecAttrService as String] as? String else { continue }
            if name == prefix || name.hasPrefix("\(prefix)-") {
                found.insert(name)
            }
        }
        return found.sorted()
    }

    /// Searches the keychain for a hashed service name matching "Claude Code-credentials-*".
    /// This uses `security dump-keychain` which can be slow or hang on some macOS
    /// versions, so it is bounded by a longer timeout and only called once per machine.
    private func findHashedServiceName() -> String? {
        // `dump-keychain` enumerates every keychain item and can be slow on large
        // keychains; give it a slightly more generous budget than other commands
        // but still a hard ceiling to prevent indefinite hangs.
        guard let result = runSecurityCommand(arguments: ["dump-keychain"], timeout: 5.0) else {
            return nil
        }

        if result.timedOut {
            LoggingService.shared.log("findHashedServiceName: `security dump-keychain` timed out — falling back to legacy name")
            return nil
        }

        guard result.exitCode == 0 else { return nil }

        let output = result.stdout
        let prefix = "Claude Code-credentials-"

        // Parse service names from dump-keychain output (format: "svce"<blob>="ServiceName")
        for line in output.components(separatedBy: "\n") {
            guard line.contains("\"svce\""), line.contains(prefix) else { continue }
            // Extract the value between quotes after the =
            if let equalsRange = line.range(of: "=\""),
               let endQuoteRange = line.range(of: "\"", range: equalsRange.upperBound..<line.endIndex) {
                let name = String(line[equalsRange.upperBound..<endQuoteRange.lowerBound])
                if name.hasPrefix(prefix) {
                    return name
                }
            }
        }
        return nil
    }

    /// Invalidates the cached service name, forcing re-discovery on next access.
    /// This also clears the persisted resolution and the discovery-attempted flag
    /// so a subsequent call will re-run the full resolution chain.
    func invalidateServiceNameCache() {
        resolvedServiceName = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.persistedServiceNameKey)
        defaults.removeObject(forKey: Self.discoveryAttemptedKey)
    }

    /// Writes credentials to `~/.claude/.credentials.json` so that
    /// `readSystemCredentials()` (which reads the file as Priority 1) returns
    /// the correct data after a profile switch. Without this, the stale file
    /// from the previous profile shadows the freshly-written keychain entry.
    private func writeCredentialsFile(_ jsonData: String) {
        let fileURL = Constants.ClaudePaths.credentialsFile
        guard let data = jsonData.data(using: .utf8) else {
            LoggingService.shared.log("writeCredentialsFile: failed to encode JSON as UTF-8")
            return
        }
        do {
            try data.write(to: fileURL, options: [.atomic])
            // .atomic replaces the inode, dropping the 0600 mode Claude Code uses for
            // this file — restore owner-only permissions on the credential-bearing file.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            LoggingService.shared.log("writeCredentialsFile: updated \(fileURL.lastPathComponent)")
        } catch {
            // Non-fatal: the keychain write is the authoritative path; the file
            // is a convenience/performance optimisation. Log and move on.
            LoggingService.shared.logError("writeCredentialsFile: failed to write \(fileURL.lastPathComponent)", error: error)
        }
    }

    /// Writes Claude Code credentials to system Keychain using security command.
    /// Every subprocess invocation is bounded by `securityCommandTimeout` so a
    /// hung `security` process cannot block the caller indefinitely.
    func writeSystemCredentials(_ jsonData: String) throws {
        let serviceName = resolveServiceName()
        LoggingService.shared.log("Writing credentials to keychain using security command (service: \(serviceName))")

        // First, delete existing item (best-effort; ignore failures)
        if let deleteResult = runSecurityCommand(arguments: [
            "delete-generic-password",
            "-s", serviceName,
            "-a", NSUserName()
        ]) {
            if deleteResult.timedOut {
                LoggingService.shared.log("writeSystemCredentials: delete step timed out, proceeding with add")
            } else if deleteResult.exitCode == 0 {
                LoggingService.shared.log("Deleted existing keychain item")
            } else {
                LoggingService.shared.log("No existing keychain item to delete (or delete failed with code \(deleteResult.exitCode))")
            }
        }

        // Add new item using security command
        guard let addResult = runSecurityCommand(arguments: [
            "add-generic-password",
            "-s", serviceName,
            "-a", NSUserName(),
            "-w", jsonData,
            "-U"  // Update if exists
        ]) else {
            throw ClaudeCodeError.keychainWriteFailed(status: -1)
        }

        if addResult.timedOut {
            LoggingService.shared.log("❌ writeSystemCredentials: add step timed out")
            throw ClaudeCodeError.keychainWriteFailed(status: -1)
        }

        if addResult.exitCode == 0 {
            LoggingService.shared.log("✅ Added Claude Code system credentials successfully using security command")
        } else {
            LoggingService.shared.log("❌ Failed to add credentials: \(addResult.stderr)")
            throw ClaudeCodeError.keychainWriteFailed(status: OSStatus(addResult.exitCode))
        }
    }

    // MARK: - Claude Code Config File (oauthAccount)

    /// Finds the actual `.claude.json` file path on disk by probing the known
    /// candidate locations. Returns nil if none exist.
    private func locateClaudeConfigFile() -> URL? {
        for candidate in Constants.ClaudePaths.claudeConfigCandidates
        where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Reads the `oauthAccount` object from Claude Code's `.claude.json` config
    /// file and returns it as a serialized JSON string. Returns nil if the file
    /// does not exist, is unreadable, or has no `oauthAccount` field.
    ///
    /// Storing the object as a raw JSON string (rather than a typed struct)
    /// preserves unknown/future fields — Claude Code may add new keys over time,
    /// and we want to faithfully round-trip whatever is present.
    func readOAuthAccount() -> String? {
        guard let url = locateClaudeConfigFile() else {
            LoggingService.shared.log("readOAuthAccount: no .claude.json config file found")
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthAccount = root["oauthAccount"] as? [String: Any] else {
            return nil
        }

        guard let serialized = try? JSONSerialization.data(
            withJSONObject: oauthAccount,
            options: [.sortedKeys]
        ),
              let jsonString = String(data: serialized, encoding: .utf8) else {
            LoggingService.shared.log("readOAuthAccount: failed to serialize oauthAccount object")
            return nil
        }

        return jsonString
    }

    /// Extracts a stable account identity from an `oauthAccount` JSON string.
    /// Prefers `accountUuid` (stable across logins), falls back to `emailAddress`.
    /// Returns nil if the JSON is missing or has neither field.
    func accountIdentity(fromOAuthAccountJSON json: String?) -> String? {
        guard let json = json,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let uuid = obj["accountUuid"] as? String, !uuid.isEmpty { return uuid }
        if let email = obj["emailAddress"] as? String, !email.isEmpty { return email }
        return nil
    }

    /// Writes an `oauthAccount` object (serialized JSON string) back into
    /// Claude Code's `.claude.json` config file, replacing whatever was there.
    /// Preserves all other top-level keys in the file. Does nothing if no
    /// `.claude.json` file exists (we don't want to create a file from scratch
    /// and accidentally overwrite user settings).
    func writeOAuthAccount(_ oauthAccountJSON: String) throws {
        guard let url = locateClaudeConfigFile() else {
            LoggingService.shared.log("writeOAuthAccount: no .claude.json config file found — skipping write")
            return
        }

        // Parse the stored oauthAccount string
        guard let newAccountData = oauthAccountJSON.data(using: .utf8),
              let newAccount = try? JSONSerialization.jsonObject(with: newAccountData) as? [String: Any] else {
            LoggingService.shared.log("writeOAuthAccount: stored oauthAccount JSON is invalid, skipping")
            throw ClaudeCodeError.invalidJSON
        }

        // Read + merge existing file (preserve all other top-level keys)
        let existingData = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
            LoggingService.shared.log("writeOAuthAccount: .claude.json root is not a JSON object")
            throw ClaudeCodeError.invalidJSON
        }

        root["oauthAccount"] = newAccount

        // Pretty-print to match Claude Code's on-disk format (best-effort)
        let updatedData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        // Atomic write so a crash mid-write can't corrupt the file
        try updatedData.write(to: url, options: [.atomic])
        LoggingService.shared.log("✓ Updated oauthAccount in \(url.lastPathComponent)")
    }

    // MARK: - Profile Sync Operations

    /// Syncs credentials from system to profile (one-time copy)
    func syncToProfile(_ profileId: UUID) throws {
        guard let jsonData = try readSystemCredentials() else {
            throw ClaudeCodeError.noCredentialsFound
        }

        // Validate JSON format
        guard let data = jsonData.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCodeError.invalidJSON
        }

        // Capture current oauthAccount from .claude.json (if present) so we can
        // restore it when this profile is re-activated. See issue #175.
        let capturedOAuthAccount = readOAuthAccount()

        // Save to profile directly
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw ClaudeCodeError.noProfileCredentials
        }

        profiles[index].cliCredentialsJSON = jsonData
        if let capturedOAuthAccount = capturedOAuthAccount {
            profiles[index].oauthAccountJSON = capturedOAuthAccount
        }
        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("Synced CLI credentials to profile: \(profileId)\(capturedOAuthAccount != nil ? " (with oauthAccount)" : "")")
    }

    /// Applies profile's CLI credentials to system (overwrites current login).
    /// Also restores the profile's captured `oauthAccount` to `~/.claude.json`
    /// so that Claude Code's `/status` command reflects the correct account
    /// after switching (see issue #175).
    func applyProfileCredentials(_ profileId: UUID) throws {
        LoggingService.shared.log("🔄 Applying CLI credentials for profile: \(profileId)")

        let profiles = ProfileStore.shared.loadProfiles()
        guard let profile = profiles.first(where: { $0.id == profileId }),
              let jsonData = profile.cliCredentialsJSON else {
            LoggingService.shared.log("❌ No CLI credentials found for profile: \(profileId)")
            throw ClaudeCodeError.noProfileCredentials
        }

        LoggingService.shared.log("📦 Found CLI credentials, writing to keychain and credentials file...")
        try writeSystemCredentials(jsonData)
        writeCredentialsFile(jsonData)

        // Restore the profile's captured oauthAccount (if any) so Claude Code's
        // /status Status tab shows the right email/org/plan for this profile.
        if let storedOAuthAccount = profile.oauthAccountJSON {
            do {
                try writeOAuthAccount(storedOAuthAccount)
            } catch {
                LoggingService.shared.logError("Failed to restore oauthAccount (non-fatal)", error: error)
            }
        } else {
            LoggingService.shared.log("Profile has no stored oauthAccount — skipping .claude.json update")
        }

        LoggingService.shared.log("✅ Applied profile CLI credentials to system: \(profileId)")
    }

    /// Removes CLI credentials from profile (doesn't affect system)
    func removeFromProfile(_ profileId: UUID) throws {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw ClaudeCodeError.noProfileCredentials
        }

        profiles[index].cliCredentialsJSON = nil
        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("Removed CLI credentials from profile: \(profileId)")
    }

    // MARK: - Access Token Extraction

    func extractAccessToken(from jsonData: String) -> String? {
        guard let data = jsonData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    }

    func extractRefreshToken(from jsonData: String) -> String? {
        guard let data = jsonData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["refreshToken"] as? String else {
            return nil
        }
        return token
    }

    func extractSubscriptionInfo(from jsonData: String) -> (type: String, scopes: [String])? {
        guard let data = jsonData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else {
            return nil
        }

        let subType = oauth["subscriptionType"] as? String ?? "unknown"
        let scopes = oauth["scopes"] as? [String] ?? []

        return (subType, scopes)
    }

    /// Extracts the token expiry date from CLI credentials JSON
    func extractTokenExpiry(from jsonData: String) -> Date? {
        guard let data = jsonData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let expiresAt = oauth["expiresAt"] as? TimeInterval else {
            return nil
        }
        // Claude Code CLI stores expiresAt in milliseconds since epoch
        // Values > 1e12 are definitely milliseconds (year 2001+ in ms vs year 33658 in seconds)
        let epochSeconds = expiresAt > 1e12 ? expiresAt / 1000.0 : expiresAt
        return Date(timeIntervalSince1970: epochSeconds)
    }

    /// Checks if the OAuth token in the credentials JSON is expired
    func isTokenExpired(_ jsonData: String) -> Bool {
        guard let expiryDate = extractTokenExpiry(from: jsonData) else {
            // No expiry info = assume valid
            return false
        }
        return Date() > expiryDate
    }

    // MARK: - OAuth Token Auto-Refresh

    /// Endpoint used by Claude Code's HUD to swap a refresh token for a fresh access token.
    /// Mirrors `TOKEN_REFRESH_URL_*` in `oh-my-claude-sisyphus/dist/hud/usage-api.js`.
    private static let oauthRefreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    /// Public OAuth client ID for Claude Code, as shipped in the HUD source.
    /// Overridable via `CLAUDE_CODE_OAUTH_CLIENT_ID` for parity with the HUD.
    private static let defaultOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// How many seconds before expiry we proactively refresh the token.
    /// Matches the HUD's 60-second leeway so a request never goes out with a token
    /// that's about to expire mid-flight.
    private static let refreshLeewaySeconds: TimeInterval = 60

    /// Reads a specific Claude Code keychain item (e.g. `Claude Code-credentials-11e1b79e`)
    /// by explicit service name, bypassing the `resolveServiceName()` chain. Used when a
    /// profile pins itself to a non-default keychain entry via
    /// `Profile.customKeychainServiceName`, so the Tracker can target the same entry Claude
    /// Code rotates during normal CLI use. Returns nil if the entry is missing, the
    /// security command timed out, or stdout was empty.
    func readKeychainCredentials(serviceName: String) -> String? {
        guard let result = runSecurityCommand(arguments: [
            "find-generic-password", "-s", serviceName, "-a", NSUserName(), "-w"
        ]) else {
            return nil
        }
        if result.timedOut {
            LoggingService.shared.log("readKeychainCredentials(svc=\(serviceName)): security command timed out")
            return nil
        }
        if result.exitCode != 0 {
            return nil
        }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Writes a credentials JSON string into a specific keychain item by explicit service name.
    /// Mirrors `writeSystemCredentials` but does not consult `resolveServiceName()` — callers
    /// supply the exact target (e.g. a hash-suffix entry tied to one Claude Code account) so
    /// rotated tokens from auto-refresh can be written back to the same place Claude Code reads.
    func writeKeychainCredentials(serviceName: String, jsonData: String) throws {
        // `-U` already updates an existing entry in place, so the previous delete-then-add
        // pattern is unnecessary and was observed to leave the entry in a partially-overwritten
        // (invalid-JSON) state under concurrent refreshes. Rely on a single atomic `-U` add.
        guard let result = runSecurityCommand(arguments: [
            "add-generic-password", "-s", serviceName, "-a", NSUserName(), "-w", jsonData, "-U"
        ]) else {
            throw ClaudeCodeError.keychainWriteFailed(status: -1)
        }
        if result.timedOut {
            throw ClaudeCodeError.keychainWriteFailed(status: -1)
        }
        if result.exitCode != 0 {
            throw ClaudeCodeError.keychainWriteFailed(status: OSStatus(result.exitCode))
        }
    }

    // internal so unit tests can construct fixtures to feed mergeRefreshedCredentials.
    struct OAuthRefreshResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String?
    }

    /// Posts the `refresh_token` grant to platform.claude.com and decodes the response.
    private func performTokenRefresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        let clientId = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_CLIENT_ID"]
            ?? Self.defaultOAuthClientID

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
        ]
        let bodyString = components.percentEncodedQuery ?? ""
        let body = Data(bodyString.utf8)

        var request = URLRequest(url: Self.oauthRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeCodeError.refreshFailed(status: -1, body: "No HTTP response")
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>"
            throw ClaudeCodeError.refreshFailed(status: http.statusCode, body: String(snippet))
        }
        return try JSONDecoder().decode(OAuthRefreshResponse.self, from: data)
    }

    /// Ensures the given profile's OAuth credentials are usable, refreshing them via the
    /// `refresh_token` grant if expired (or near-expired). Returns the up-to-date credentials
    /// JSON on success, or `nil` if the profile has no usable source, no refresh token, or
    /// the network refresh failed.
    ///
    /// Source-of-truth selection:
    /// - If `profile.customKeychainServiceName` is set, the Tracker reads the latest tokens
    ///   directly from that keychain entry. Claude Code rotates tokens into the same entry
    ///   during normal CLI use, so the read is usually already fresh — no network call needed.
    /// - Otherwise, falls back to `profile.cliCredentialsJSON` (legacy behavior).
    ///
    /// On a successful refresh, the new credentials are written back to BOTH the profile's
    /// cached JSON AND (when applicable) the custom keychain entry, so Claude Code and the
    /// Tracker stay in sync.
    func ensureFreshCredentials(for profileId: UUID) async -> String? {
        let profiles = ProfileStore.shared.loadProfiles()
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            return nil
        }

        let customSvc = profile.customKeychainServiceName

        // ACTIVE profile without a pin: Claude Code itself owns this token lineage in
        // the system keychain and rotates it during use. NEVER refresh it ourselves —
        // our refresh would consume the refresh token out from under the CLI, making
        // its next refresh fail with invalid_grant ("Please run /login"). Instead,
        // READ the system credentials (Claude keeps them fresh) and mirror them into
        // the profile when they belong to the same account.
        if customSvc == nil, ProfileStore.shared.loadActiveProfileId() == profileId {
            if let systemJSON = try? readSystemCredentials() {
                let systemIdentity = accountIdentity(fromOAuthAccountJSON: readOAuthAccount())
                let profileIdentity = accountIdentity(fromOAuthAccountJSON: profile.oauthAccountJSON)
                let sameAccount = (systemIdentity != nil && systemIdentity == profileIdentity)
                    || extractRefreshToken(from: systemJSON) == profile.cliCredentialsJSON.flatMap(extractRefreshToken)
                if sameAccount {
                    if !isTokenExpired(systemJSON) {
                        persistProfileCredentialsJSON(profileId: profileId, json: systemJSON)
                        return systemJSON
                    }
                    // System token EXPIRED: Claude Code refreshes ~60s BEFORE expiry
                    // while in use, so an expired keychain token means the CLI is idle
                    // (sleep/inactivity — #268). Safe window to take over the rotation
                    // ONCE — but the rotated lineage MUST be handed back to the system
                    // keychain (+ mirror file), or the CLI would be left holding a
                    // consumed refresh token and forced to /login.
                    if let refreshToken = extractRefreshToken(from: systemJSON) {
                        do {
                            let refreshed = try await performTokenRefresh(refreshToken: refreshToken)
                            if let updatedJSON = mergeRefreshedCredentials(into: systemJSON, refreshed: refreshed) {
                                do {
                                    try writeSystemCredentials(updatedJSON)
                                    writeCredentialsFile(updatedJSON)
                                } catch {
                                    LoggingService.shared.logError("ensureFreshCredentials: refreshed active-profile tokens but keychain writeback failed — CLI may need /login", error: error)
                                }
                                persistProfileCredentialsJSON(profileId: profileId, json: updatedJSON)
                                LoggingService.shared.log("✓ ensureFreshCredentials: refreshed idle active-profile token and wrote back to system keychain")
                                return updatedJSON
                            }
                        } catch {
                            LoggingService.shared.logError("ensureFreshCredentials: idle active-profile refresh failed (non-fatal)", error: error)
                        }
                    }
                    // Refresh unavailable/failed — return the expired snapshot without
                    // rotating anything; the CLI recovers it on next use.
                    return systemJSON
                }
            }
            // Different account in system, or no system creds — fall back to the cached
            // snapshot WITHOUT refreshing; never rotate a lineage the CLI may own.
            return profile.cliCredentialsJSON
        }

        var initialJSON: String?
        if let svc = customSvc {
            initialJSON = readKeychainCredentials(serviceName: svc)
            if initialJSON == nil {
                LoggingService.shared.logError("ensureFreshCredentials: profile '\(profile.name)' pins keychain '\(svc)' but it was not found")
            } else if extractRefreshToken(from: initialJSON!) == nil {
                // Keychain payload exists but is corrupt (e.g. invalid JSON after a prior bad
                // write). Fall back to the profile's cached plist credentials so we still have
                // a refresh_token to try — better than going dormant.
                LoggingService.shared.logError("ensureFreshCredentials: keychain '\(svc)' payload for '\(profile.name)' is unparseable; falling back to plist cliCredentialsJSON")
                initialJSON = profile.cliCredentialsJSON
            }
        } else {
            initialJSON = profile.cliCredentialsJSON
        }

        guard let cliJSON = initialJSON else {
            return nil
        }

        // Fast path: token still valid beyond the leeway window.
        if let expiryDate = extractTokenExpiry(from: cliJSON),
           expiryDate.timeIntervalSinceNow > Self.refreshLeewaySeconds {
            // If we sourced from a custom keychain entry, mirror its current contents into the
            // profile cache so display code (menu bar, popover) sees the up-to-date tokens.
            if customSvc != nil {
                persistProfileCredentialsJSON(profileId: profileId, json: cliJSON)
            }
            return cliJSON
        }

        guard let refreshToken = extractRefreshToken(from: cliJSON) else {
            LoggingService.shared.log("ensureFreshCredentials: profile '\(profile.name)' has no refresh token; cannot auto-refresh")
            return nil
        }

        let sourceTag = customSvc.map { "keychain:\($0)" } ?? "plist"
        LoggingService.shared.log("ensureFreshCredentials: refreshing OAuth token for profile '\(profile.name)' (source=\(sourceTag))")

        let refreshed: OAuthRefreshResponse
        do {
            refreshed = try await performTokenRefresh(refreshToken: refreshToken)
        } catch let ClaudeCodeError.refreshFailed(status, body) {
            // Surface the error body for diagnosis. 4xx responses never contain access
            // tokens — only `{ "error": "...", "error_description": "..." }` style payloads —
            // so logging it is safe.
            LoggingService.shared.logError("ensureFreshCredentials: refresh failed for '\(profile.name)' (HTTP \(status)) body=\(body)")
            return nil
        } catch {
            LoggingService.shared.logError("ensureFreshCredentials: refresh failed for '\(profile.name)'", error: error)
            return nil
        }

        guard let updatedJSON = mergeRefreshedCredentials(into: cliJSON, refreshed: refreshed) else {
            LoggingService.shared.logError("ensureFreshCredentials: failed to merge refreshed credentials for '\(profile.name)'")
            return nil
        }

        // Write back: always update the profile cache; if we sourced from a custom keychain
        // entry, also persist the rotated tokens there so Claude Code's next read picks them up.
        persistProfileCredentialsJSON(profileId: profileId, json: updatedJSON)
        if let svc = customSvc {
            do {
                try writeKeychainCredentials(serviceName: svc, jsonData: updatedJSON)
            } catch {
                LoggingService.shared.logError("ensureFreshCredentials: refreshed but failed to write back to keychain '\(svc)'", error: error)
            }
        }

        LoggingService.shared.log("✓ ensureFreshCredentials: refreshed and saved for profile '\(profile.name)'")
        return updatedJSON
    }

    /// Re-loads profiles and writes `json` into the profile's `cliCredentialsJSON` if it
    /// differs from what's already stored. Re-loading inside the call minimizes the risk
    /// of clobbering concurrent edits to other profile fields.
    private func persistProfileCredentialsJSON(profileId: UUID, json: String) {
        var reloaded = ProfileStore.shared.loadProfiles()
        guard let idx = reloaded.firstIndex(where: { $0.id == profileId }),
              reloaded[idx].cliCredentialsJSON != json else {
            return
        }
        reloaded[idx].cliCredentialsJSON = json
        ProfileStore.shared.saveProfiles(reloaded)
    }

    /// Merges an OAuth refresh response into the existing `claudeAiOauth` payload,
    /// preserving fields the refresh response does not touch (scopes, subscriptionType, etc.).
    // internal so unit tests can verify the merge correctness against fixtures.
    func mergeRefreshedCredentials(into cliJSON: String, refreshed: OAuthRefreshResponse) -> String? {
        guard let data = cliJSON.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            return nil
        }

        oauth["accessToken"] = refreshed.access_token
        if let newRT = refreshed.refresh_token {
            oauth["refreshToken"] = newRT
        }
        // Claude Code persists `expiresAt` in milliseconds since the Unix epoch.
        let newExpiryMs = Int64(Date().timeIntervalSince1970 * 1000)
            + Int64(refreshed.expires_in) * 1000
        oauth["expiresAt"] = newExpiryMs

        root["claudeAiOauth"] = oauth

        // Single-line, sorted-keys output. Avoid `prettyPrinted` here because the
        // resulting JSON is round-tripped through `security add-generic-password -w`,
        // and embedded newlines have been observed to corrupt the stored payload on
        // some macOS builds — readers then see "Extra data" parse errors.
        guard let outData = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.sortedKeys]),
              let outString = String(data: outData, encoding: .utf8) else {
            return nil
        }
        return outString
    }

    // MARK: - Auto Re-sync Before Switching

    /// Re-syncs credentials from system Keychain before profile switching
    /// This ensures we always have the latest CLI login when switching profiles
    func resyncBeforeSwitching(for profileId: UUID) throws {
        LoggingService.shared.log("Re-syncing CLI credentials before profile switch: \(profileId)")

        // Read fresh credentials from system (if user is logged in)
        guard let freshJSON = try readSystemCredentials() else {
            // No credentials in system - user not logged into CLI anymore
            LoggingService.shared.log("No system credentials found - skipping re-sync")
            return
        }

        // Validate JSON before saving (defense-in-depth against truncated data)
        guard let data = freshJSON.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LoggingService.shared.log("Re-synced credentials contain invalid JSON - skipping save")
            return
        }

        // Verify the system credentials belong to the same account as this profile.
        // IMPORTANT: compare ACCOUNT IDENTITY (oauthAccount.accountUuid), not refresh
        // tokens. Claude Code ROTATES refresh tokens during normal use, so for the same
        // account the system refresh token routinely differs from our stored snapshot —
        // that rotation is exactly what we must capture here, or the profile keeps a
        // consumed refresh token and every later refresh fails with invalid_grant.
        var profiles = ProfileStore.shared.loadProfiles()
        if let profile = profiles.first(where: { $0.id == profileId }) {
            let systemIdentity = accountIdentity(fromOAuthAccountJSON: readOAuthAccount())
            let profileIdentity = accountIdentity(fromOAuthAccountJSON: profile.oauthAccountJSON)
            if let sys = systemIdentity, let stored = profileIdentity {
                if sys != stored {
                    LoggingService.shared.log("⚠️ resyncBeforeSwitching: skipping for '\(profile.name)' — system account (\(sys)) differs from profile account (\(stored))")
                    return
                }
                // Same account — capture even though the refresh token rotated.
            } else if let storedJSON = profile.cliCredentialsJSON {
                // Identity unavailable on one side — fall back to the conservative
                // refresh-token equality check to avoid cross-profile contamination.
                let freshRefreshToken = extractRefreshToken(from: freshJSON)
                let storedRefreshToken = extractRefreshToken(from: storedJSON)
                if let fresh = freshRefreshToken, let stored = storedRefreshToken, fresh != stored {
                    LoggingService.shared.log("⚠️ resyncBeforeSwitching: skipping for '\(profile.name)' — no account identity available and refresh token differs")
                    return
                }
                // A manually pasted setup token has neither an oauthAccount id
                // nor a refreshToken, so no identity check can vouch that the
                // system keychain belongs to the same account — never overwrite
                // the manual token with potentially foreign credentials.
                if storedRefreshToken == nil && profileIdentity == nil {
                    LoggingService.shared.log("⚠️ resyncBeforeSwitching: skipping for '\(profile.name)' — profile uses a manual setup token; account identity unverifiable")
                    return
                }
            }
        }

        // Capture latest oauthAccount too, so if the user logged in with a
        // different account since the last sync we keep the profile's
        // `.claude.json` identity in sync with its keychain credentials.
        let freshOAuthAccount = readOAuthAccount()

        // Update profile's stored credentials with fresh ones (profiles already loaded above)
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return
        }

        profiles[index].cliCredentialsJSON = freshJSON
        if let freshOAuthAccount = freshOAuthAccount {
            profiles[index].oauthAccountJSON = freshOAuthAccount
        }
        profiles[index].cliAccountSyncedAt = Date()  // Update sync timestamp
        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("✓ Re-synced CLI credentials from system and updated timestamp\(freshOAuthAccount != nil ? " (with oauthAccount)" : "")")
    }
}

// MARK: - ClaudeCodeError

enum ClaudeCodeError: LocalizedError {
    case noCredentialsFound
    case invalidJSON
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case noProfileCredentials
    case refreshFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noCredentialsFound:
            return "No Claude Code credentials found in system Keychain. Please log in to Claude Code first."
        case .invalidJSON:
            return "Claude Code credentials are corrupted or invalid."
        case .keychainReadFailed(let status):
            return "Failed to read credentials from system Keychain (status: \(status))."
        case .keychainWriteFailed(let status):
            return "Failed to write credentials to system Keychain (status: \(status))."
        case .noProfileCredentials:
            return "This profile has no synced CLI account."
        case .refreshFailed(let status, _):
            return "OAuth token refresh failed (status: \(status))."
        }
    }
}
