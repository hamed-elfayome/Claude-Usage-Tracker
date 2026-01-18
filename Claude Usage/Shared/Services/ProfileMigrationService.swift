//
//  ProfileMigrationService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

/// Handles migration from single-profile (v2.x) to multi-profile system (v3.0)
class ProfileMigrationService {
    static let shared = ProfileMigrationService()

    private let migrationKey = "didMigrateToProfilesV3"

    private init() {}

    func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            LoggingService.shared.log("Profile migration already completed")
            return
        }

        LoggingService.shared.log("Starting migration to multi-profile system...")

        do {
            // 1. Create first profile from existing settings
            let firstProfile = createFirstProfileFromLegacy()

            // 2. Migrate credentials from old Keychain keys to profile-specific keys
            try migrateCredentialsToProfile(firstProfile.id)

            // 3. Save first profile
            ProfileStore.shared.saveProfiles([firstProfile])
            ProfileStore.shared.saveActiveProfileId(firstProfile.id)
            ProfileStore.shared.saveDisplayMode(.single)

            // 4. Mark migration complete
            UserDefaults.standard.set(true, forKey: migrationKey)

            LoggingService.shared.log("Migration complete. First profile: \(firstProfile.name)")
        } catch {
            LoggingService.shared.logError("Migration failed", error: error)
            // Don't mark as complete so it can retry
        }
    }

    private func createFirstProfileFromLegacy() -> Profile {
        let dataStore = DataStore.shared

        // Generate a funny name for the first profile
        let profileName = FunnyNameGenerator.getRandomName(excluding: [])

        // Load existing settings
        let iconConfig = dataStore.loadMenuBarIconConfiguration()
        let refreshInterval = dataStore.loadRefreshInterval()
        let notificationsEnabled = dataStore.loadNotificationsEnabled()
        let autoStartSessionEnabled = dataStore.loadAutoStartSessionEnabled()

        return Profile(
            id: UUID(),
            name: profileName,
            hasCliAccount: false,
            cliAccountSyncedAt: nil,
            iconConfig: iconConfig,
            refreshInterval: refreshInterval,
            autoStartSessionEnabled: autoStartSessionEnabled,
            notificationSettings: NotificationSettings(
                enabled: notificationsEnabled,
                threshold75Enabled: true,
                threshold90Enabled: true,
                threshold95Enabled: true
            ),
            isSelectedForDisplay: true,
            createdAt: Date(),
            lastUsedAt: Date()
        )
    }

    private func migrateCredentialsToProfile(_ profileId: UUID) throws {
        let keychain = KeychainService.shared
        let dataStore = DataStore.shared
        let profileStore = ProfileStore.shared

        LoggingService.shared.log("Migrating credentials to profile: \(profileId)")

        var profiles = profileStore.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            LoggingService.shared.log("Profile not found for migration")
            return
        }

        // Migrate Claude.ai session key from old Keychain location
        if let sessionKey = try? keychain.load(for: .claudeSessionKey) {
            profiles[index].claudeSessionKey = sessionKey
            LoggingService.shared.log("Migrated Claude session key")
        }

        // Migrate API Console session key
        if let apiKey = try? keychain.load(for: .apiSessionKey) {
            profiles[index].apiSessionKey = apiKey
            LoggingService.shared.log("Migrated API session key")
        }

        // Migrate organization IDs from DataStore
        if let orgId = dataStore.loadOrganizationId() {
            profiles[index].organizationId = orgId
            LoggingService.shared.log("Migrated organization ID")
        }

        if let apiOrgId = dataStore.loadAPIOrganizationId() {
            profiles[index].apiOrganizationId = apiOrgId
            LoggingService.shared.log("Migrated API organization ID")
        }

        profileStore.saveProfiles(profiles)

        // Note: Don't delete old keys yet for safety - can be cleaned up in a future version

        LoggingService.shared.log("Credential migration complete")
    }

    /// Resets migration flag for testing purposes
    func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        LoggingService.shared.log("Reset migration flag")
    }
}
