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

    private init() {}

    // MARK: - System Keychain Access

    /// Reads Claude Code credentials from system Keychain using security command
    func readSystemCredentials() throws -> String? {
        let username = NSUserName()
        LoggingService.shared.log("ClaudeCodeSync: Reading credentials for user '\(username)'...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-a", username,
            "-w"  // Print password only
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let exitCode = process.terminationStatus
        LoggingService.shared.log("ClaudeCodeSync: security command exit code = \(exitCode)")

        if exitCode == 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let value = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                LoggingService.shared.log("ClaudeCodeSync: Failed to decode output as UTF-8")
                throw ClaudeCodeError.invalidJSON
            }
            LoggingService.shared.log("ClaudeCodeSync: Successfully read credentials (\(value.count) chars)")
            return value
        } else if exitCode == 44 {
            // Exit code 44 = item not found
            LoggingService.shared.log("ClaudeCodeSync: No keychain item found (exit 44)")
            return nil
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            LoggingService.shared.log("ClaudeCodeSync: Failed to read keychain (exit \(exitCode)): \(errorString)")
            throw ClaudeCodeError.keychainReadFailed(status: OSStatus(exitCode))
        }
    }

    /// Writes Claude Code credentials to system Keychain using security command
    func writeSystemCredentials(_ jsonData: String) throws {
        LoggingService.shared.log("Writing credentials to keychain using security command")

        // First, delete existing item
        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        deleteProcess.arguments = [
            "delete-generic-password",
            "-s", "Claude Code-credentials",
            "-a", NSUserName()
        ]

        try deleteProcess.run()
        deleteProcess.waitUntilExit()

        let deleteExitCode = deleteProcess.terminationStatus
        if deleteExitCode == 0 {
            LoggingService.shared.log("Deleted existing keychain item")
        } else {
            LoggingService.shared.log("No existing keychain item to delete (or delete failed with code \(deleteExitCode))")
        }

        // Add new item using security command
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        addProcess.arguments = [
            "add-generic-password",
            "-s", "Claude Code-credentials",
            "-a", NSUserName(),
            "-w", jsonData,
            "-U"  // Update if exists
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        addProcess.standardOutput = outputPipe
        addProcess.standardError = errorPipe

        try addProcess.run()
        addProcess.waitUntilExit()

        let exitCode = addProcess.terminationStatus

        if exitCode == 0 {
            LoggingService.shared.log("✅ Added Claude Code system credentials successfully using security command")
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            LoggingService.shared.log("❌ Failed to add credentials: \(errorString)")
            throw ClaudeCodeError.keychainWriteFailed(status: OSStatus(exitCode))
        }
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

        // Save to profile via Keychain-backed credential store
        var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
        creds.cliCredentialsJSON = jsonData
        try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

        LoggingService.shared.log("Synced CLI credentials to profile: \(profileId)")
    }

    /// Applies profile's CLI credentials to system (overwrites current login)
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

        LoggingService.shared.log("✅ Applied profile CLI credentials to system: \(profileId)")
    }

    /// Removes CLI credentials from profile (doesn't affect system)
    func removeFromProfile(_ profileId: UUID) throws {
        // Clear cliCredentialsJSON in the Keychain-backed credential store
        var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
        creds.cliCredentialsJSON = nil
        try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

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
        // expiresAt may be in seconds or milliseconds; normalize to seconds
        let expirySec = expiresAt > 1e12 ? expiresAt / 1000.0 : expiresAt
        return Date(timeIntervalSince1970: expirySec)
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

    /// Re-syncs credentials from system Keychain before profile switching.
    /// Only updates the profile if the keychain credentials actually belong to it
    /// (matched by refresh token) to prevent cross-contamination.
    func resyncBeforeSwitching(for profileId: UUID) throws {
        LoggingService.shared.log("Re-syncing CLI credentials before profile switch: \(profileId)")

        // Read fresh credentials from system (if user is logged in)
        guard let freshJSON = try readSystemCredentials() else {
            LoggingService.shared.log("No system credentials found - skipping re-sync")
            return
        }

        // Verify the keychain credentials belong to this profile by comparing refresh tokens.
        // Refresh tokens are stable across access-token rotations, so they reliably identify accounts.
        let profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return
        }
        let profile = profiles[index]

        if let storedJSON = profile.cliCredentialsJSON,
           let storedRefresh = extractRefreshToken(from: storedJSON),
           let freshRefresh = extractRefreshToken(from: freshJSON) {
            if storedRefresh != freshRefresh {
                // Keychain has a different account's credentials — do NOT overwrite this profile.
                LoggingService.shared.log("⚠️ Keychain refresh token doesn't match profile '\(profile.name)' — skipping re-sync to prevent cross-contamination")
                // Try to find the profile that actually owns these credentials
                if let ownerProfile = profiles.first(where: {
                    if let json = $0.cliCredentialsJSON, let rt = extractRefreshToken(from: json) {
                        return rt == freshRefresh
                    }
                    return false
                }) {
                    var ownerCreds = try ProfileStore.shared.loadProfileCredentials(ownerProfile.id)
                    ownerCreds.cliCredentialsJSON = freshJSON
                    try ProfileStore.shared.saveProfileCredentials(ownerProfile.id, credentials: ownerCreds)
                    LoggingService.shared.log("✓ Re-synced keychain credentials to actual owner profile '\(ownerProfile.name)' instead")
                }
                return
            }
        }

        // Refresh tokens match (or profile has no stored creds yet) — safe to update via Keychain
        var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
        creds.cliCredentialsJSON = freshJSON
        try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

        // Update sync timestamp in profile metadata
        var updatedProfiles = ProfileStore.shared.loadProfiles()
        if let idx = updatedProfiles.firstIndex(where: { $0.id == profileId }) {
            updatedProfiles[idx].cliAccountSyncedAt = Date()
            ProfileStore.shared.saveProfiles(updatedProfiles)
        }

        LoggingService.shared.log("✓ Re-synced CLI credentials for profile '\(profile.name)'")
    }
}

// MARK: - ClaudeCodeError

enum ClaudeCodeError: LocalizedError {
    case noCredentialsFound
    case invalidJSON
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case noProfileCredentials

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
        }
    }
}
