//
//  ProfileManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation
import Combine

@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var displayMode: ProfileDisplayMode = .single
    @Published var multiProfileConfig: MultiProfileDisplayConfig = .default
    @Published var isSwitchingProfile: Bool = false

    private let profileStore = ProfileStore.shared
    private let cliSyncService = ClaudeCodeSyncService.shared

    private var switchingSemaphore = false

    private init() {}

    // MARK: - Initialization

    func loadProfiles() {
        profiles = profileStore.loadProfiles()

        // Ensure minimum 1 profile
        if profiles.isEmpty {
            let defaultProfile = createDefaultProfile()
            profiles = [defaultProfile]
            profileStore.saveProfiles(profiles)

            // On first launch, try to sync CLI credentials to the new default profile
            syncCLICredentialsToDefaultProfile(defaultProfile.id)
        }

        migrateLegacyCodexProfileIfNeeded()

        // Load active profile
        if let activeId = profileStore.loadActiveProfileId(),
           let profile = profiles.first(where: { $0.id == activeId }) {
            activeProfile = profile
        } else {
            activeProfile = profiles.first
            if let first = profiles.first {
                profileStore.saveActiveProfileId(first.id)
            }
        }

        displayMode = profileStore.loadDisplayMode()
        multiProfileConfig = profileStore.loadMultiProfileConfig()

        LoggingService.shared.log("ProfileManager: Loaded \(profiles.count) profile(s), active: \(activeProfile?.name ?? "none")")
    }

    // MARK: - Profile Operations

    func createProfile(
        name: String? = nil,
        provider: ProfileProvider = .claude,
        copySettingsFrom: Profile? = nil
    ) -> Profile {
        let usedNames = profiles.map { $0.name }
        let profileName = name ?? FunnyNameGenerator.getRandomName(excluding: usedNames)
        let copiedProfile = copySettingsFrom?.provider == provider ? copySettingsFrom : nil

        let newProfile = Profile(
            id: UUID(),
            name: profileName,
            provider: provider,
            hasCliAccount: false,
            codexConfiguration: copiedProfile?.codexConfiguration ?? CodexProfileConfiguration(),
            iconConfig: copiedProfile?.iconConfig
                ?? (provider == .codex ? .codexProfileDefault : .default),
            refreshInterval: copiedProfile?.refreshInterval ?? 30.0,
            autoStartSessionEnabled: provider == .claude
                ? (copiedProfile?.autoStartSessionEnabled ?? false)
                : false,
            checkOverageLimitEnabled: copiedProfile?.checkOverageLimitEnabled ?? true,
            notificationSettings: copiedProfile?.notificationSettings ?? NotificationSettings(),
            isSelectedForDisplay: true
        )

        profiles.append(newProfile)
        profileStore.saveProfiles(profiles)

        LoggingService.shared.log("Created new profile: \(newProfile.name)")
        return newProfile
    }

    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile

            if activeProfile?.id == profile.id {
                activeProfile = profile

                // Detailed logging for credential state
                LoggingService.shared.log("ProfileManager.updateProfile: Updated ACTIVE profile '\(profile.name)'")
                LoggingService.shared.log("  - claudeSessionKey: \(profile.claudeSessionKey == nil ? "NIL" : "EXISTS (len: \(profile.claudeSessionKey!.count))")")
                LoggingService.shared.log("  - organizationId: \(profile.organizationId == nil ? "NIL" : "EXISTS")")
                LoggingService.shared.log("  - hasClaudeAI: \(profile.hasClaudeAI)")
                LoggingService.shared.log("  - hasAnyCredentials: \(profile.hasAnyCredentials)")
                LoggingService.shared.log("  - claudeUsage: \(profile.claudeUsage == nil ? "NIL" : "EXISTS")")
            } else {
                LoggingService.shared.log("Updated profile: \(profile.name) (not active)")
            }

            profileStore.saveProfiles(profiles)
        }
    }

    func deleteProfile(_ id: UUID) throws {
        guard profiles.count > 1 else {
            throw ProfileError.cannotDeleteLastProfile
        }

        let profileName = profiles.first(where: { $0.id == id })?.name ?? "unknown"

        // Clean up usage history for this profile
        UsageHistoryService.shared.deleteHistory(for: id)
        LoggingService.shared.log("Successfully deleted usage history for profile: \(profileName)")

        profiles.removeAll { $0.id == id }

        // Remove the profile's credentials from the Keychain (they no longer live
        // in the profiles plist — #267).
        profileStore.deleteProfileSecrets(id)

        // Switch to first profile if deleted active
        if activeProfile?.id == id {
            if let first = profiles.first {
                Task {
                    await activateProfile(first.id)
                }
            }
        }

        profileStore.saveProfiles(profiles)
        NotificationCenter.default.post(name: .profileDeleted, object: id)
        LoggingService.shared.log("Deleted profile: \(profileName)")
    }

    func toggleProfileSelection(_ id: UUID) {
        // Use async to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.profiles.firstIndex(where: { $0.id == id }) {
                self.profiles[index].isSelectedForDisplay.toggle()
                self.profileStore.saveProfiles(self.profiles)
            }
        }
    }

    func getSelectedProfiles() -> [Profile] {
        displayMode == .single
            ? [activeProfile].compactMap { $0 }
            : profiles.filter { $0.isSelectedForDisplay }
    }

    func updateDisplayMode(_ mode: ProfileDisplayMode) {
        // Use async to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async { [weak self] in
            self?.displayMode = mode
            self?.profileStore.saveDisplayMode(mode)
            LoggingService.shared.log("Updated display mode to: \(mode.rawValue)")
        }
    }

    func updateMultiProfileConfig(_ config: MultiProfileDisplayConfig) {
        // Use async to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async { [weak self] in
            self?.multiProfileConfig = config
            self?.profileStore.saveMultiProfileConfig(config)
            LoggingService.shared.log("Updated multi-profile config: style=\(config.iconStyle.rawValue), showWeek=\(config.showWeek)")
        }
    }

    // MARK: - Profile Activation (Centralized)

    func activateProfile(_ id: UUID) async {
        guard !switchingSemaphore else {
            LoggingService.shared.log("Profile switch already in progress, ignoring")
            return
        }

        guard let profile = profiles.first(where: { $0.id == id }) else {
            LoggingService.shared.log("Profile not found: \(id)")
            return
        }

        if activeProfile?.id == id {
            LoggingService.shared.log("Profile already active: \(profile.name)")
            return
        }

        switchingSemaphore = true
        isSwitchingProfile = true

        LoggingService.shared.log("Switching to profile: \(profile.name)")

        // Re-sync current profile before leaving (if CLI credentials exist)
        if let currentProfile = activeProfile,
           currentProfile.provider == .claude,
           currentProfile.cliCredentialsJSON != nil {
            do {
                try cliSyncService.resyncBeforeSwitching(for: currentProfile.id)
                // Reload profiles to get the updated data in memory
                profiles = profileStore.loadProfiles()
                LoggingService.shared.log("✓ Re-synced current profile before switching")
            } catch {
                LoggingService.shared.logError("Failed to re-sync current profile (non-fatal)", error: error)
            }
        }

        // Reload profiles from disk to get latest data (including any resyncs from other profiles)
        profiles = profileStore.loadProfiles()

        // Get the updated target profile from the reloaded data
        guard let updatedProfile = profiles.first(where: { $0.id == id }) else {
            LoggingService.shared.log("Profile not found after reload: \(id)")
            switchingSemaphore = false
            isSwitchingProfile = false
            return
        }

        // Apply new profile's CLI credentials (if available)
        LoggingService.shared.log("Checking CLI credentials for profile '\(updatedProfile.name)': hasJSON=\(updatedProfile.cliCredentialsJSON != nil)")

        if updatedProfile.provider == .claude, updatedProfile.cliCredentialsJSON != nil {
            // Refresh the OAuth token before applying. Stored tokens expire (~8h),
            // so applying a stale snapshot would write a dead access token to the
            // keychain and Claude Code would 401 ("Please run /login"). This refreshes
            // via the refresh_token grant and persists the rotated tokens back to the
            // profile, so applyProfileCredentials below writes a valid token.
            if let refreshed = await cliSyncService.ensureFreshCredentials(for: updatedProfile.id) {
                LoggingService.shared.log("✓ Ensured fresh credentials before apply for: \(updatedProfile.name)")
                _ = refreshed
                // Reload so applyProfileCredentials picks up the refreshed token.
                profiles = profileStore.loadProfiles()
            }
            do {
                try cliSyncService.applyProfileCredentials(updatedProfile.id)
                LoggingService.shared.log("✓ Applied CLI credentials for: \(updatedProfile.name)")
            } catch {
                LoggingService.shared.logError("Failed to apply CLI credentials (non-fatal)", error: error)
            }
        } else if updatedProfile.provider == .claude {
            LoggingService.shared.log("⚠️ Profile '\(updatedProfile.name)' has no CLI credentials JSON")
        } else {
            LoggingService.shared.log("Codex profile activation does not change Claude Code credentials")
        }

        // Update last used timestamp
        var updated = updatedProfile
        updated.lastUsedAt = Date()

        if let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
            profiles[index] = updated
        }

        activeProfile = updated
        profileStore.saveActiveProfileId(id)
        profileStore.saveProfiles(profiles)

        // Update statusline script if the new profile has credentials
        if updated.provider == .claude,
           updated.claudeSessionKey != nil,
           updated.organizationId != nil {
            do {
                try StatuslineService.shared.updateScriptsIfInstalled()
                LoggingService.shared.log("✓ Updated statusline for profile: \(updated.name)")
            } catch {
                LoggingService.shared.logError("Failed to update statusline (non-fatal)", error: error)
            }
        }

        // Update profile name in statusline config
        if updated.provider == .claude {
            do {
                try StatuslineService.shared.updateProfileNameInConfig(updated.name)
            } catch {
                LoggingService.shared.logError("Failed to update statusline profile name (non-fatal)", error: error)
            }
        }

        switchingSemaphore = false
        isSwitchingProfile = false

        LoggingService.shared.log("Successfully activated profile: \(updatedProfile.name)")
    }

    // MARK: - Credentials

    func loadCredentials(for profileId: UUID) throws -> ProfileCredentials {
        return try profileStore.loadProfileCredentials(profileId)
    }

    func saveCredentials(for profileId: UUID, credentials: ProfileCredentials) throws {
        try profileStore.saveProfileCredentials(profileId, credentials: credentials)

        // Update profile in memory
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].claudeSessionKey = credentials.claudeSessionKey
            profiles[index].organizationId = credentials.organizationId
            profiles[index].apiSessionKey = credentials.apiSessionKey
            profiles[index].apiOrganizationId = credentials.apiOrganizationId
            profiles[index].cliCredentialsJSON = credentials.cliCredentialsJSON

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }
        }
    }

    /// Removes Claude.ai credentials for a profile
    func removeClaudeAICredentials(for profileId: UUID) throws {
        // Load and clear credentials from Keychain
        var creds = try profileStore.loadProfileCredentials(profileId)
        creds.claudeSessionKey = nil
        creds.organizationId = nil
        try profileStore.saveProfileCredentials(profileId, credentials: creds)

        // Update Profile model in memory
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].claudeSessionKey = nil
            profiles[index].organizationId = nil
            profiles[index].claudeUsage = nil  // Clear saved usage data

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }

        LoggingService.shared.log("ProfileManager: Removed Claude.ai credentials for profile \(profileId)")

        // Post single notification for credential change
        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
    }

    /// Removes API Console credentials for a profile
    func removeAPICredentials(for profileId: UUID) throws {
        // Load and clear credentials from Keychain
        var creds = try profileStore.loadProfileCredentials(profileId)
        creds.apiSessionKey = nil
        creds.apiOrganizationId = nil
        try profileStore.saveProfileCredentials(profileId, credentials: creds)

        // Update Profile model in memory
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].apiSessionKey = nil
            profiles[index].apiOrganizationId = nil
            profiles[index].apiUsage = nil  // Clear saved usage data

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }

        LoggingService.shared.log("ProfileManager: Removed API credentials for profile \(profileId)")

        // Post single notification for credential change
        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
    }

    // MARK: - Usage Data

    /// Saves Claude usage data for a specific profile
    func saveClaudeUsage(_ usage: ClaudeUsage, for profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            LoggingService.shared.logError("saveClaudeUsage: Profile not found with ID: \(profileId)")
            return
        }

        profiles[index].claudeUsage = usage

        // Update activeProfile reference if it's the same profile
        if activeProfile?.id == profileId {
            activeProfile = profiles[index]
        }

        // Save to persistent storage
        profileStore.saveProfiles(profiles)
        LoggingService.shared.log("Saved Claude usage for profile: \(profiles[index].name)")
    }

    /// Loads Claude usage data for a specific profile
    func loadClaudeUsage(for profileId: UUID) -> ClaudeUsage? {
        return profiles.first(where: { $0.id == profileId })?.claudeUsage
    }

    /// Saves API usage data for a specific profile
    func saveAPIUsage(_ usage: APIUsage, for profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            LoggingService.shared.logError("saveAPIUsage: Profile not found with ID: \(profileId)")
            return
        }

        profiles[index].apiUsage = usage

        // Update activeProfile reference if it's the same profile
        if activeProfile?.id == profileId {
            activeProfile = profiles[index]
        }

        // Save to persistent storage
        profileStore.saveProfiles(profiles)
        LoggingService.shared.log("Saved API usage for profile: \(profiles[index].name)")
    }

    /// Loads API usage data for a specific profile
    func loadAPIUsage(for profileId: UUID) -> APIUsage? {
        return profiles.first(where: { $0.id == profileId })?.apiUsage
    }

    func saveCodexUsage(_ usage: CodexUsage, for profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            LoggingService.shared.logError("saveCodexUsage: Profile not found with ID: \(profileId)")
            return
        }
        profiles[index].codexUsage = usage
        if activeProfile?.id == profileId {
            activeProfile = profiles[index]
        }
        profileStore.saveProfiles(profiles)
        LoggingService.shared.log("Saved Codex usage for profile: \(profiles[index].name)")
    }

    // MARK: - Profile Settings

    /// Updates icon configuration for a profile
    func updateIconConfig(_ config: MenuBarIconConfiguration, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].iconConfig = config

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates refresh interval for a profile
    func updateRefreshInterval(_ interval: TimeInterval, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].refreshInterval = interval

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates auto-start session setting for a profile
    func updateAutoStartSessionEnabled(_ enabled: Bool, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].autoStartSessionEnabled = enabled

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates check overage limit setting for a profile
    func updateCheckOverageLimitEnabled(_ enabled: Bool, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].checkOverageLimitEnabled = enabled

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates notification settings for a profile
    func updateNotificationSettings(_ settings: NotificationSettings, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].notificationSettings = settings

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates organization ID for a profile
    func updateOrganizationId(_ orgId: String?, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].organizationId = orgId

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    /// Updates API organization ID for a profile
    func updateAPIOrganizationId(_ orgId: String?, for profileId: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].apiOrganizationId = orgId

            if activeProfile?.id == profileId {
                activeProfile = profiles[index]
            }

            profileStore.saveProfiles(profiles)
        }
    }

    // MARK: - Private Helpers

    /// Syncs CLI credentials to default profile on first launch only
    private func syncCLICredentialsToDefaultProfile(_ profileId: UUID) {
        do {
            // Attempt to read credentials from system Keychain
            guard let jsonData = try cliSyncService.readSystemCredentials() else {
                LoggingService.shared.log("ProfileManager: No CLI credentials found in system Keychain")
                return
            }

            // Validate: not expired
            if cliSyncService.isTokenExpired(jsonData) {
                LoggingService.shared.log("ProfileManager: CLI credentials found but expired")
                return
            }

            // Validate: has valid access token
            guard cliSyncService.extractAccessToken(from: jsonData) != nil else {
                LoggingService.shared.log("ProfileManager: CLI credentials found but missing access token")
                return
            }

            // Sync to the newly created default profile
            try cliSyncService.syncToProfile(profileId)

            // Reload the profile to get updated credentials
            profiles = profileStore.loadProfiles()

            LoggingService.shared.log("ProfileManager: ✅ Successfully synced CLI credentials to default profile on first launch")

        } catch {
            LoggingService.shared.logError("ProfileManager: Failed to sync CLI credentials on first launch (non-fatal)", error: error)
            // Non-fatal: profile will be created without credentials
            // User can manually sync in settings
        }
    }

    private func createDefaultProfile() -> Profile {
        Profile(
            name: FunnyNameGenerator.getRandomName(excluding: []),
            provider: .claude,
            iconConfig: .default,
            refreshInterval: 30.0,
            autoStartSessionEnabled: false,
            checkOverageLimitEnabled: true,
            notificationSettings: NotificationSettings()
        )
    }

    private func migrateLegacyCodexProfileIfNeeded() {
        let sharedStore = SharedDataStore.shared
        guard !sharedStore.codexProfileMigrationCompleted else { return }
        defer { sharedStore.codexProfileMigrationCompleted = true }
        guard !profiles.contains(where: { $0.provider == .codex }),
              sharedStore.hasStoredCodexSettings else { return }

        let legacy = sharedStore.loadCodexSettings()
        guard legacy.monitoringEnabled,
              legacy.menuBarMetric.isEnabled || DataStore.shared.loadCodexUsage() != nil else {
            return
        }

        var iconConfig = MenuBarIconConfiguration.codexProfileDefault
        if let index = iconConfig.metrics.firstIndex(where: { $0.metricType == .codex }) {
            var metric = legacy.menuBarMetric
            metric.metricType = .codex
            metric.isEnabled = true
            iconConfig.metrics[index] = metric
        }
        let notificationSettings = NotificationSettings(
            enabled: legacy.notificationsEnabled,
            threshold75Enabled: legacy.notificationThresholds.contains(75),
            threshold90Enabled: legacy.notificationThresholds.contains(90),
            threshold95Enabled: legacy.notificationThresholds.contains(95),
            customThresholds: legacy.notificationThresholds.filter { ![75, 90, 95].contains($0) }
        )
        let profile = Profile(
            name: "Codex",
            provider: .codex,
            codexUsage: DataStore.shared.loadCodexUsage(),
            codexConfiguration: CodexProfileConfiguration(
                executablePath: legacy.executablePath,
                selectedRateLimitID: legacy.selectedRateLimitID,
                showAccountEmail: legacy.showAccountEmail
            ),
            iconConfig: iconConfig,
            notificationSettings: notificationSettings
        )
        profiles.append(profile)
        profileStore.saveProfiles(profiles)
        LoggingService.shared.log("Migrated legacy Codex monitoring into profile '\(profile.name)'")
    }

}

// MARK: - ProfileError

enum ProfileError: LocalizedError {
    case cannotDeleteLastProfile

    var errorDescription: String? {
        switch self {
        case .cannotDeleteLastProfile:
            return "Cannot delete the last profile. At least one profile is required."
        }
    }
}
