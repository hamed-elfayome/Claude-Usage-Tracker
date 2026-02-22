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

    // MARK: - Profile Credential Migration

    private let profileCredentialMigrationKey = "keychainMigration_profileCredentials_v1"

    /// Migrates profile credentials from UserDefaults (plaintext JSON) to Keychain.
    /// This reads the raw profiles_v3 blob via JSONSerialization to access credential
    /// fields that are no longer included in Profile's CodingKeys.
    func migrateProfileCredentialsIfNeeded() {
        if UserDefaults.standard.bool(forKey: profileCredentialMigrationKey) {
            return
        }

        LoggingService.shared.log("Starting profile credential migration to Keychain")

        guard let data = UserDefaults.standard.data(forKey: "profiles_v3") else {
            // No profiles to migrate
            UserDefaults.standard.set(true, forKey: profileCredentialMigrationKey)
            return
        }

        // Decode as raw JSON to access credential fields that CodingKeys now excludes
        guard let profilesArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            UserDefaults.standard.set(true, forKey: profileCredentialMigrationKey)
            return
        }

        let keychain = KeychainService.shared
        var migratedCount = 0
        var failureCount = 0

        for profileDict in profilesArray {
            guard let idString = profileDict["id"] as? String else { continue }
            let account = idString

            for field in ProfileKeychainKey.allFields {
                if let value = profileDict[field] as? String, !value.isEmpty {
                    let service = ProfileKeychainKey.service(for: field)
                    do {
                        try keychain.save(value, service: service, account: account)
                        migratedCount += 1
                    } catch {
                        LoggingService.shared.logError("Failed to migrate \(field) for profile \(idString): \(error)")
                        failureCount += 1
                    }
                }
            }
        }

        if failureCount > 0 {
            // Don't mark complete or strip credentials if any migration failed
            LoggingService.shared.logError("Profile credential migration incomplete: \(failureCount) failure(s)")
            return
        }

        // Re-save profiles to strip credentials from UserDefaults.
        // The updated CodingKeys in Profile will exclude credential fields on encode.
        let profileStore = ProfileStore.shared
        let profiles = profileStore.loadProfiles()
        profileStore.saveProfiles(profiles)

        UserDefaults.standard.set(true, forKey: profileCredentialMigrationKey)
        LoggingService.shared.log("Profile credential migration complete: migrated \(migratedCount) credential(s)")
    }

    /// Resets the migration flag (for testing purposes)
    func resetMigrationForTesting() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: profileCredentialMigrationKey)
        LoggingService.shared.log("Reset Keychain migration flags for testing")
    }
}
