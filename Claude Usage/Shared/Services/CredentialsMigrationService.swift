//
//  CredentialsMigrationService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-03-02.
//

import Foundation

/// One-time migration of profile credentials from plaintext UserDefaults to macOS Keychain.
///
/// On first run after update: reads profiles from UserDefaults (with credentials still embedded),
/// copies each profile's credentials to Keychain, then re-saves profiles to UserDefaults without
/// credential fields. Non-destructive: Keychain write happens first, UserDefaults strip second.
class CredentialsMigrationService {
    static let shared = CredentialsMigrationService()

    private let migrationKey = "didMigrateCredentialsToKeychain_v1"
    private let keychainService = KeychainService.shared

    private init() {}

    /// Performs migration if it hasn't been done yet. Safe to call on every launch.
    func migrateIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        LoggingService.shared.log("CredentialsMigration: Starting migration from UserDefaults to Keychain")

        // Read raw profiles from UserDefaults (may still contain embedded credentials)
        guard let data = UserDefaults.standard.data(forKey: "profiles_v3") else {
            // No profiles at all — mark done so we don't check again
            UserDefaults.standard.set(true, forKey: migrationKey)
            LoggingService.shared.log("CredentialsMigration: No profiles found, marking complete")
            return
        }

        guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
            LoggingService.shared.logError("CredentialsMigration: Failed to decode profiles, will retry next launch")
            return
        }

        var migratedCount = 0

        for profile in profiles {
            let hasAny = profile.claudeSessionKey != nil
                || profile.organizationId != nil
                || profile.apiSessionKey != nil
                || profile.apiOrganizationId != nil
                || profile.cliCredentialsJSON != nil

            guard hasAny else { continue }

            let credentials = ProfileCredentials(
                claudeSessionKey: profile.claudeSessionKey,
                organizationId: profile.organizationId,
                apiSessionKey: profile.apiSessionKey,
                apiOrganizationId: profile.apiOrganizationId,
                cliCredentialsJSON: profile.cliCredentialsJSON
            )

            do {
                try keychainService.saveProfileCredentials(profile.id, credentials: credentials)
                migratedCount += 1
                LoggingService.shared.log("CredentialsMigration: Migrated credentials for profile '\(profile.name)' (\(profile.id))")
            } catch {
                LoggingService.shared.logError("CredentialsMigration: Failed to save credentials for profile '\(profile.name)': \(error.localizedDescription)")
                // Don't set the flag — retry on next launch
                return
            }
        }

        // Now strip credentials from UserDefaults by re-saving without them
        let stripped = profiles.map { profile -> Profile in
            var p = profile
            p.claudeSessionKey = nil
            p.organizationId = nil
            p.apiSessionKey = nil
            p.apiOrganizationId = nil
            p.cliCredentialsJSON = nil
            return p
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let strippedData = try encoder.encode(stripped)
            UserDefaults.standard.set(strippedData, forKey: "profiles_v3")
            LoggingService.shared.log("CredentialsMigration: Stripped credentials from UserDefaults")
        } catch {
            LoggingService.shared.logError("CredentialsMigration: Failed to re-save stripped profiles: \(error.localizedDescription)")
            // Credentials are already in Keychain, so this is non-fatal.
            // The next loadProfiles() call will strip them anyway.
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        LoggingService.shared.log("CredentialsMigration: Complete. Migrated \(migratedCount) profile(s)")
    }
}
