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
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // For debugging
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
            // Hydrate credential fields from Keychain (they are excluded from Codable)
            for i in profiles.indices {
                if let creds = try? loadProfileCredentials(profiles[i].id) {
                    profiles[i].claudeSessionKey = creds.claudeSessionKey
                    profiles[i].organizationId = creds.organizationId
                    profiles[i].apiSessionKey = creds.apiSessionKey
                    profiles[i].apiOrganizationId = creds.apiOrganizationId
                    profiles[i].cliCredentialsJSON = creds.cliCredentialsJSON
                }
            }
            LoggingService.shared.log("ProfileStore: Loaded \(profiles.count) profiles from storage")
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

    // MARK: - Credential Helpers (Keychain-backed)

    /// Saves profile credentials to the macOS Keychain.
    /// Each credential field is stored as a separate Keychain item keyed by profile UUID.
    func saveProfileCredentials(_ profileId: UUID, credentials: ProfileCredentials) throws {
        let account = profileId.uuidString

        let fieldValues: [(String, String?)] = [
            ("claudeSessionKey", credentials.claudeSessionKey),
            ("organizationId", credentials.organizationId),
            ("apiSessionKey", credentials.apiSessionKey),
            ("apiOrganizationId", credentials.apiOrganizationId),
            ("cliCredentialsJSON", credentials.cliCredentialsJSON),
        ]

        for (field, value) in fieldValues {
            let service = ProfileKeychainKey.service(for: field)
            if let value = value {
                try keychainService.save(value, service: service, account: account)
            } else {
                try keychainService.delete(service: service, account: account)
            }
        }
    }

    /// Loads profile credentials from the macOS Keychain.
    func loadProfileCredentials(_ profileId: UUID) throws -> ProfileCredentials {
        let account = profileId.uuidString

        return ProfileCredentials(
            claudeSessionKey: try keychainService.load(
                service: ProfileKeychainKey.service(for: "claudeSessionKey"), account: account),
            organizationId: try keychainService.load(
                service: ProfileKeychainKey.service(for: "organizationId"), account: account),
            apiSessionKey: try keychainService.load(
                service: ProfileKeychainKey.service(for: "apiSessionKey"), account: account),
            apiOrganizationId: try keychainService.load(
                service: ProfileKeychainKey.service(for: "apiOrganizationId"), account: account),
            cliCredentialsJSON: try keychainService.load(
                service: ProfileKeychainKey.service(for: "cliCredentialsJSON"), account: account)
        )
    }

    /// Deletes all Keychain credentials for a profile.
    /// Call this when a profile is deleted to avoid orphaned Keychain entries.
    func deleteProfileCredentials(_ profileId: UUID) {
        let account = profileId.uuidString
        for field in ProfileKeychainKey.allFields {
            let service = ProfileKeychainKey.service(for: field)
            try? keychainService.delete(service: service, account: account)
        }
        LoggingService.shared.log("ProfileStore: Deleted Keychain credentials for profile \(profileId)")
    }
}
