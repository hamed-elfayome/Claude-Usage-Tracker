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
        do {
            // Strip credential fields before writing to UserDefaults
            let stripped = profiles.map { profile -> Profile in
                var p = profile
                p.claudeSessionKey = nil
                p.organizationId = nil
                p.apiSessionKey = nil
                p.apiOrganizationId = nil
                p.cliCredentialsJSON = nil
                return p
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(stripped)
            defaults.set(data, forKey: Keys.profiles)

            if let savedData = defaults.data(forKey: Keys.profiles) {
                LoggingService.shared.log("ProfileStore: Saved \(profiles.count) profiles (\(savedData.count) bytes, credentials stripped)")
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
            LoggingService.shared.log("ProfileStore: Loaded \(profiles.count) profiles from storage")

            // Hydrate credentials from Keychain
            for i in profiles.indices {
                let creds = keychainService.loadProfileCredentials(profiles[i].id)
                profiles[i].claudeSessionKey = creds.claudeSessionKey
                profiles[i].organizationId = creds.organizationId
                profiles[i].apiSessionKey = creds.apiSessionKey
                profiles[i].apiOrganizationId = creds.apiOrganizationId
                profiles[i].cliCredentialsJSON = creds.cliCredentialsJSON
            }

            return profiles
        } catch {
            LoggingService.shared.logStorageError("loadProfiles", error: error)
            LoggingService.shared.logError("ProfileStore: Failed to decode profiles, returning empty array")
            return []
        }
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
        try keychainService.saveProfileCredentials(profileId, credentials: credentials)
        LoggingService.shared.log("ProfileStore: Saved credentials to Keychain for profile \(profileId)")
    }

    func loadProfileCredentials(_ profileId: UUID) -> ProfileCredentials {
        return keychainService.loadProfileCredentials(profileId)
    }
}
