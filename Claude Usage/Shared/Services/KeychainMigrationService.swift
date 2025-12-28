//
//  KeychainMigrationService.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-28.
//

import Foundation

/// Service for migrating session keys from file-based and UserDefaults storage to Keychain
class KeychainMigrationService {
    static let shared = KeychainMigrationService()

    private init() {}

    private let migrationCompletedKey = "keychainMigrationCompleted_v1"

    /// Performs one-time migration of session keys to Keychain
    func performMigrationIfNeeded() {
        // Check if migration has already been completed
        if UserDefaults.standard.bool(forKey: migrationCompletedKey) {
            LoggingService.shared.log("Keychain migration already completed, skipping")
            return
        }

        LoggingService.shared.log("Starting Keychain migration")

        var migratedCount = 0

        // 1. Migrate Claude.ai session key from file
        migratedCount += migrateClaudeSessionKeyFromFile()

        // 2. Migrate API session key from UserDefaults
        migratedCount += migrateAPISessionKeyFromUserDefaults()

        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)

        if migratedCount > 0 {
            LoggingService.shared.log("Keychain migration completed: migrated \(migratedCount) key(s)")
        } else {
            LoggingService.shared.log("Keychain migration completed: no keys to migrate")
        }
    }

    /// Migrates Claude.ai session key from ~/.claude-session-key file to Keychain
    /// - Returns: 1 if migrated, 0 if not needed
    private func migrateClaudeSessionKeyFromFile() -> Int {
        // Check if key already exists in Keychain
        if KeychainService.shared.exists(for: .claudeSessionKey) {
            LoggingService.shared.log("Claude session key already in Keychain, skipping file migration")
            return 0
        }

        let sessionKeyPath = Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: sessionKeyPath.path) else {
            LoggingService.shared.log("No Claude session key file found to migrate")
            return 0
        }

        do {
            // Read from file
            let fileKey = try String(contentsOf: sessionKeyPath, encoding: .utf8)
            let trimmedKey = fileKey.trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate before migrating
            let validator = SessionKeyValidator()
            guard validator.isValid(trimmedKey) else {
                LoggingService.shared.log("Claude session key in file is invalid, skipping migration")
                return 0
            }

            // Save to Keychain
            try KeychainService.shared.save(trimmedKey, for: .claudeSessionKey)

            // Delete the file (it will be recreated by StatuslineService if statusline is enabled)
            try FileManager.default.removeItem(at: sessionKeyPath)

            LoggingService.shared.log("Migrated Claude session key from file to Keychain")
            return 1

        } catch {
            LoggingService.shared.log("Failed to migrate Claude session key from file: \(error.localizedDescription)")
            return 0
        }
    }

    /// Migrates API session key from UserDefaults to Keychain
    /// - Returns: 1 if migrated, 0 if not needed
    private func migrateAPISessionKeyFromUserDefaults() -> Int {
        // Check if key already exists in Keychain
        if KeychainService.shared.exists(for: .apiSessionKey) {
            LoggingService.shared.log("API session key already in Keychain, skipping UserDefaults migration")

            // Clean up UserDefaults even if Keychain already has the key
            if UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.apiSessionKey) != nil {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.apiSessionKey)
                LoggingService.shared.log("Cleaned up API session key from UserDefaults")
            }

            return 0
        }

        // Check if key exists in UserDefaults
        guard let legacyKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.apiSessionKey) else {
            LoggingService.shared.log("No API session key found in UserDefaults to migrate")
            return 0
        }

        do {
            // Save to Keychain
            try KeychainService.shared.save(legacyKey, for: .apiSessionKey)

            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.apiSessionKey)

            LoggingService.shared.log("Migrated API session key from UserDefaults to Keychain")
            return 1

        } catch {
            LoggingService.shared.log("Failed to migrate API session key from UserDefaults: \(error.localizedDescription)")
            return 0
        }
    }

    /// Resets the migration flag (for testing purposes)
    func resetMigrationForTesting() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        LoggingService.shared.log("Reset Keychain migration flag for testing")
    }
}
