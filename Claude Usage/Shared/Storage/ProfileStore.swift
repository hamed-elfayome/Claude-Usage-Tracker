//
//  ProfileStore.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

/// Manages storage and retrieval of profiles and profile-related data
class ProfileStore {
    static let shared = ProfileStore()

    private let defaults: UserDefaults
    private let keychainService = KeychainService.shared

    private enum Keys {
        static let profiles = "profiles_v3"
        static let activeProfileId = "activeProfileId"
        static let displayMode = "profileDisplayMode"
        static let multiProfileConfig = "multiProfileDisplayConfig"
    }

    init() {
        // Use standard UserDefaults (app container)
        self.defaults = UserDefaults.standard
        LoggingService.shared.log("ProfileStore: Using standard app container storage")
    }

    // MARK: - Profile Management

    func saveProfiles(_ profiles: [Profile]) {
        // Persist credential fields to the Keychain FIRST; the plist encoding below
        // excludes them (#267 / GHSA-mfxh-xpwm-23c7 — the plist is cleartext on disk).
        var allSecretsInKeychain = true
        for profile in profiles {
            allSecretsInKeychain = persistSecrets(of: profile) && allSecretsInKeychain
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // For debugging
            if !allSecretsInKeychain {
                // Zero-data-loss fallback: if any Keychain write failed, keep the
                // credentials in the plist for this save so nothing is lost; the
                // migration retries on the next save.
                encoder.userInfo[Profile.includeSecretsKey] = true
                LoggingService.shared.logError("ProfileStore: Keychain write failed — keeping credentials in plist for this save (will retry)")
            }
            let data = try encoder.encode(profiles)
            defaults.set(data, forKey: Keys.profiles)

            // Verify save
            if let savedData = defaults.data(forKey: Keys.profiles) {
                LoggingService.shared.log("ProfileStore: Saved \(profiles.count) profiles (\(savedData.count) bytes)")
            } else {
                LoggingService.shared.logError("ProfileStore: Failed to verify save!")
            }
        } catch {
            LoggingService.shared.logStorageError("saveProfiles", error: error)
        }
    }

    func loadProfiles() -> [Profile] {
        guard let data = defaults.data(forKey: Keys.profiles) else {
            LoggingService.shared.log("ProfileStore: No profiles found in storage")
            return []
        }

        do {
            var profiles = try JSONDecoder().decode([Profile].self, from: data)

            // Hydrate credential fields from the Keychain. A value still present in
            // the plist wins (it is either pre-migration, or was written by an older
            // app version more recently than our Keychain copy) and gets migrated on
            // the save below.
            var plistHadSecrets = false
            for i in profiles.indices {
                let id = profiles[i].id
                if profiles[i].claudeSessionKey != nil {
                    plistHadSecrets = true
                } else {
                    profiles[i].claudeSessionKey = keychainService.loadProfileSecret(profileId: id, field: .claudeSessionKey)
                }
                if profiles[i].apiSessionKey != nil {
                    plistHadSecrets = true
                } else {
                    profiles[i].apiSessionKey = keychainService.loadProfileSecret(profileId: id, field: .apiSessionKey)
                }
                if profiles[i].cliCredentialsJSON != nil {
                    plistHadSecrets = true
                } else {
                    profiles[i].cliCredentialsJSON = keychainService.loadProfileSecret(profileId: id, field: .cliCredentialsJSON)
                }
            }

            if plistHadSecrets {
                LoggingService.shared.log("ProfileStore: migrating plaintext credentials from plist to Keychain (#267)")
                saveProfiles(profiles)  // writes Keychain + scrubbed plist (or keeps plist on failure)
            }

            LoggingService.shared.log("ProfileStore: Loaded \(profiles.count) profiles from storage")
            return profiles
        } catch {
            LoggingService.shared.logStorageError("loadProfiles", error: error)
            LoggingService.shared.logError("ProfileStore: Failed to decode profiles, returning empty array")
            return []
        }
    }

    /// Writes a profile's credential fields to the Keychain (nil deletes the item so a
    /// signed-out credential can't be resurrected). Returns false if any write failed.
    /// Every non-nil write is READ BACK and byte-compared before we trust it — the
    /// plist copy is only ever scrubbed for values proven to be retrievable.
    private func persistSecrets(of profile: Profile) -> Bool {
        var ok = true
        ok = persistSecret(profile.claudeSessionKey, profile.id, .claudeSessionKey) && ok
        ok = persistSecret(profile.apiSessionKey, profile.id, .apiSessionKey) && ok
        ok = persistSecret(profile.cliCredentialsJSON, profile.id, .cliCredentialsJSON) && ok
        return ok
    }

    private func persistSecret(_ value: String?, _ profileId: UUID, _ field: KeychainService.ProfileSecretField) -> Bool {
        guard keychainService.saveProfileSecret(value, profileId: profileId, field: field) else {
            return false
        }
        guard let value = value else { return true }  // deletions need no read-back
        return keychainService.verifyProfileSecret(value, profileId: profileId, field: field)
    }

    /// Removes a deleted profile's Keychain items.
    func deleteProfileSecrets(_ profileId: UUID) {
        keychainService.deleteAllProfileSecrets(profileId: profileId)
    }

    func saveActiveProfileId(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Keys.activeProfileId)
    }

    func loadActiveProfileId() -> UUID? {
        guard let uuidString = defaults.string(forKey: Keys.activeProfileId) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    func saveDisplayMode(_ mode: ProfileDisplayMode) {
        defaults.set(mode.rawValue, forKey: Keys.displayMode)
    }

    func loadDisplayMode() -> ProfileDisplayMode {
        guard let rawValue = defaults.string(forKey: Keys.displayMode),
              let mode = ProfileDisplayMode(rawValue: rawValue) else {
            return .single
        }
        return mode
    }

    // MARK: - Multi-Profile Display Config

    func saveMultiProfileConfig(_ config: MultiProfileDisplayConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: Keys.multiProfileConfig)
        } catch {
            LoggingService.shared.logStorageError("saveMultiProfileConfig", error: error)
        }
    }

    func loadMultiProfileConfig() -> MultiProfileDisplayConfig {
        guard let data = defaults.data(forKey: Keys.multiProfileConfig) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(MultiProfileDisplayConfig.self, from: data)
        } catch {
            LoggingService.shared.logStorageError("loadMultiProfileConfig", error: error)
            return .default
        }
    }

    // MARK: - Credential Helpers

    func saveProfileCredentials(_ profileId: UUID, credentials: ProfileCredentials) throws {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw NSError(domain: "ProfileStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])
        }

        // Update credentials directly in profile
        profiles[index].claudeSessionKey = credentials.claudeSessionKey
        profiles[index].organizationId = credentials.organizationId
        profiles[index].apiSessionKey = credentials.apiSessionKey
        profiles[index].apiOrganizationId = credentials.apiOrganizationId
        profiles[index].cliCredentialsJSON = credentials.cliCredentialsJSON

        saveProfiles(profiles)
    }

    func loadProfileCredentials(_ profileId: UUID) throws -> ProfileCredentials {
        let profiles = loadProfiles()
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            throw NSError(domain: "ProfileStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])
        }

        return ProfileCredentials(
            claudeSessionKey: profile.claudeSessionKey,
            organizationId: profile.organizationId,
            apiSessionKey: profile.apiSessionKey,
            apiOrganizationId: profile.apiOrganizationId,
            cliCredentialsJSON: profile.cliCredentialsJSON
        )
    }
}
