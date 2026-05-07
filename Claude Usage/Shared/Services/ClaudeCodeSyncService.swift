//
//  ClaudeCodeSyncService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation
import Security

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

    // MARK: - System Credentials Access (Fallback Chain)

    /// Reads Claude Code credentials using a fallback chain:
    /// 1. ~/.claude/.credentials.json (always complete, not subject to keychain truncation)
    /// 2. System Keychain (may be truncated for large payloads >2KB)
    /// 3. Regex extraction of accessToken from truncated keychain data (last resort)
    func readSystemCredentials() throws -> String? {
        // 1. Try credentials file first (most reliable)
        if let fileJSON = readCredentialsFile() {
            LoggingService.shared.log("Read credentials from .credentials.json file")
            return fileJSON
        }

        // 2. Try keychain
        let keychainData = try readKeychainCredentials()

        guard let rawJSON = keychainData else {
            // No credentials anywhere
            return nil
        }

        // 3. Validate keychain JSON
        if let data = rawJSON.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return rawJSON
        }

        // 4. Keychain data is truncated/invalid — try regex extraction
        LoggingService.shared.log("Keychain JSON is invalid (likely truncated), attempting regex extraction")
        if let token = extractAccessTokenViaRegex(from: rawJSON) {
            let minimalJSON = "{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}"
            LoggingService.shared.log("Built minimal credentials from regex-extracted token")
            return minimalJSON
        }

        // 5. All attempts failed
        throw ClaudeCodeError.invalidJSON
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

        LoggingService.shared.log("📦 Found CLI credentials, writing to keychain...")
        try writeSystemCredentials(jsonData)

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

    /// Saves a manually-pasted long-lived OAuth token (from `claude setup-token`)
    /// to the given profile. Wraps the bare token in a minimal `claudeAiOauth`
    /// JSON envelope so the rest of the app can consume it through the same
    /// extraction helpers used for synced credentials.
    ///
    /// Long-lived setup tokens have no `expiresAt` field, which intentionally
    /// causes `isTokenExpired` to return `false` ("no expiry info = assume valid"),
    /// which is the desired behavior — these tokens don't expire on a short cycle.
    func saveManualOAuthToken(_ token: String, profileId: UUID) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClaudeCodeError.invalidToken
        }

        let payload: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": trimmed,
                "subscriptionType": "manual",
                "scopes": ["user:inference", "user:profile"]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw ClaudeCodeError.invalidJSON
        }

        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw ClaudeCodeError.noProfileCredentials
        }

        profiles[index].cliCredentialsJSON = jsonString
        profiles[index].hasCliAccount = true
        profiles[index].cliAccountSyncedAt = Date()
        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("Saved manual OAuth setup token to profile: \(profileId)")
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
        // The refreshToken is session-scoped and only changes on explicit /login — a
        // mismatch means the keychain holds another account's data (written by
        // applyProfileCredentials for a different profile). Saving would corrupt this profile.
        var profiles = ProfileStore.shared.loadProfiles()
        if let profile = profiles.first(where: { $0.id == profileId }),
           let storedJSON = profile.cliCredentialsJSON {
            let freshRefreshToken = extractRefreshToken(from: freshJSON)
            let storedRefreshToken = extractRefreshToken(from: storedJSON)
            if let fresh = freshRefreshToken, let stored = storedRefreshToken, fresh != stored {
                LoggingService.shared.log("⚠️ resyncBeforeSwitching: skipping for '\(profile.name)' — system refresh token differs (different account)")
                return
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
    case invalidToken
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case noProfileCredentials

    var errorDescription: String? {
        switch self {
        case .noCredentialsFound:
            return "No Claude Code credentials found in system Keychain. Please log in to Claude Code first."
        case .invalidJSON:
            return "Claude Code credentials are corrupted or invalid."
        case .invalidToken:
            return "OAuth token is empty or invalid. Run `claude setup-token` and paste the full token."
        case .keychainReadFailed(let status):
            return "Failed to read credentials from system Keychain (status: \(status))."
        case .keychainWriteFailed(let status):
            return "Failed to write credentials to system Keychain (status: \(status))."
        case .noProfileCredentials:
            return "This profile has no synced CLI account."
        }
    }
}
