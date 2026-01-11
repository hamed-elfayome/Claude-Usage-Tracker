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
    }

    init() {
        if let groupDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) {
            self.defaults = groupDefaults
        } else {
            self.defaults = UserDefaults.standard
        }
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
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
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
