//
//  Profile.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

/// Represents a complete isolated profile with all credentials and settings
struct Profile: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID
    var name: String

    // MARK: - Credentials (stored directly in profile)
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var apiSessionKeyExpiry: Date?
    var cliCredentialsJSON: String?

    // MARK: - CLI Account Sync Metadata
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    /// Optional override that pins this profile to a specific Claude Code keychain
    /// service entry (e.g. `Claude Code-credentials-11e1b79e`) as the source of truth
    /// for OAuth credentials. When set, refresh-aware reads bypass the cached
    /// `cliCredentialsJSON` and pull fresh tokens directly from that keychain item —
    /// which is what Claude Code rotates during normal use. Lets users with multiple
    /// CLAUDE_CONFIG_DIR installs map each Tracker profile to its own keychain entry.
    var customKeychainServiceName: String?

    /// Serialized `oauthAccount` object from Claude Code's `.claude.json` config file.
    /// Captured at sync time and re-applied during profile switches so that
    /// Claude Code's `/status` command shows the correct account for the active
    /// profile. Stored as a raw JSON string to preserve unknown/future fields
    /// (emailAddress, accountUuid, organizationName, billingType, etc.).
    var oauthAccountJSON: String?

    // MARK: - Usage Data (Per-Profile)
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?

    // MARK: - Appearance Settings (Per-Profile)
    var iconConfig: MenuBarIconConfiguration

    // MARK: - Behavior Settings (Per-Profile)
    var refreshInterval: TimeInterval
    var autoStartSessionEnabled: Bool
    var checkOverageLimitEnabled: Bool

    /// Optional personal monthly spend target, in minor units (cents), used as the
    /// denominator for the "Monthly Spend" bar in the popover. `nil` (or 0) means
    /// no target set — the popover then shows the spend amount without a bar.
    var monthlySpendLimitCents: Double?

    // MARK: - Notification Settings (Per-Profile)
    var notificationSettings: NotificationSettings

    // MARK: - Display Configuration
    var isSelectedForDisplay: Bool  // For multi-profile menu bar mode

    // MARK: - Metadata
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        claudeSessionKey: String? = nil,
        organizationId: String? = nil,
        apiSessionKey: String? = nil,
        apiOrganizationId: String? = nil,
        apiSessionKeyExpiry: Date? = nil,
        cliCredentialsJSON: String? = nil,
        hasCliAccount: Bool = false,
        cliAccountSyncedAt: Date? = nil,
        customKeychainServiceName: String? = nil,
        oauthAccountJSON: String? = nil,
        claudeUsage: ClaudeUsage? = nil,
        apiUsage: APIUsage? = nil,
        iconConfig: MenuBarIconConfiguration = .default,
        refreshInterval: TimeInterval = 30.0,
        autoStartSessionEnabled: Bool = false,
        checkOverageLimitEnabled: Bool = true,
        monthlySpendLimitCents: Double? = nil,
        notificationSettings: NotificationSettings = NotificationSettings(),
        isSelectedForDisplay: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.claudeSessionKey = claudeSessionKey
        self.organizationId = organizationId
        self.apiSessionKey = apiSessionKey
        self.apiOrganizationId = apiOrganizationId
        self.apiSessionKeyExpiry = apiSessionKeyExpiry
        self.cliCredentialsJSON = cliCredentialsJSON
        self.hasCliAccount = hasCliAccount
        self.cliAccountSyncedAt = cliAccountSyncedAt
        self.customKeychainServiceName = customKeychainServiceName
        self.oauthAccountJSON = oauthAccountJSON
        self.claudeUsage = claudeUsage
        self.apiUsage = apiUsage
        self.iconConfig = iconConfig
        self.refreshInterval = refreshInterval
        self.autoStartSessionEnabled = autoStartSessionEnabled
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.monthlySpendLimitCents = monthlySpendLimitCents
        self.notificationSettings = notificationSettings
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Codable (secrets excluded — #267 / GHSA-mfxh-xpwm-23c7)

    /// When set to `true` in `encoder.userInfo`, the credential fields are included
    /// in the encoded output. Used ONLY as a zero-data-loss fallback when a Keychain
    /// write fails during save — never in the normal persistence path.
    static let includeSecretsKey = CodingUserInfoKey(rawValue: "profileIncludeSecrets")!

    private enum CodingKeys: String, CodingKey {
        case id, name
        case claudeSessionKey, organizationId
        case apiSessionKey, apiOrganizationId, apiSessionKeyExpiry
        case cliCredentialsJSON
        case hasCliAccount, cliAccountSyncedAt
        case customKeychainServiceName
        case oauthAccountJSON
        case claudeUsage, apiUsage
        case iconConfig
        case refreshInterval, autoStartSessionEnabled, checkOverageLimitEnabled
        case monthlySpendLimitCents
        case notificationSettings
        case isSelectedForDisplay
        case createdAt, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Secrets: present only in legacy (pre-Keychain-migration) plists; hydrated
        // from the Keychain by ProfileStore after decoding.
        claudeSessionKey = try c.decodeIfPresent(String.self, forKey: .claudeSessionKey)
        organizationId = try c.decodeIfPresent(String.self, forKey: .organizationId)
        apiSessionKey = try c.decodeIfPresent(String.self, forKey: .apiSessionKey)
        apiOrganizationId = try c.decodeIfPresent(String.self, forKey: .apiOrganizationId)
        apiSessionKeyExpiry = try c.decodeIfPresent(Date.self, forKey: .apiSessionKeyExpiry)
        cliCredentialsJSON = try c.decodeIfPresent(String.self, forKey: .cliCredentialsJSON)
        hasCliAccount = try c.decodeIfPresent(Bool.self, forKey: .hasCliAccount) ?? false
        cliAccountSyncedAt = try c.decodeIfPresent(Date.self, forKey: .cliAccountSyncedAt)
        customKeychainServiceName = try c.decodeIfPresent(String.self, forKey: .customKeychainServiceName)
        oauthAccountJSON = try c.decodeIfPresent(String.self, forKey: .oauthAccountJSON)
        // Usage values are re-fetchable caches — a malformed cache (e.g. written
        // by a different app version) must degrade to nil, never fail the
        // profile decode and wipe the profile list.
        claudeUsage = (try? c.decodeIfPresent(ClaudeUsage.self, forKey: .claudeUsage)) ?? nil
        apiUsage = (try? c.decodeIfPresent(APIUsage.self, forKey: .apiUsage)) ?? nil
        iconConfig = try c.decodeIfPresent(MenuBarIconConfiguration.self, forKey: .iconConfig) ?? .default
        refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 30.0
        autoStartSessionEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoStartSessionEnabled) ?? false
        checkOverageLimitEnabled = try c.decodeIfPresent(Bool.self, forKey: .checkOverageLimitEnabled) ?? true
        monthlySpendLimitCents = try c.decodeIfPresent(Double.self, forKey: .monthlySpendLimitCents)
        notificationSettings = try c.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings) ?? NotificationSettings()
        isSelectedForDisplay = try c.decodeIfPresent(Bool.self, forKey: .isSelectedForDisplay) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        // Credentials live in the Keychain (per-profile items), NOT in the plist.
        // The plist on disk is world-readable cleartext — see #267.
        if (encoder.userInfo[Profile.includeSecretsKey] as? Bool) == true {
            try c.encodeIfPresent(claudeSessionKey, forKey: .claudeSessionKey)
            try c.encodeIfPresent(apiSessionKey, forKey: .apiSessionKey)
            try c.encodeIfPresent(cliCredentialsJSON, forKey: .cliCredentialsJSON)
        }
        try c.encodeIfPresent(organizationId, forKey: .organizationId)
        try c.encodeIfPresent(apiOrganizationId, forKey: .apiOrganizationId)
        try c.encodeIfPresent(apiSessionKeyExpiry, forKey: .apiSessionKeyExpiry)
        try c.encode(hasCliAccount, forKey: .hasCliAccount)
        try c.encodeIfPresent(cliAccountSyncedAt, forKey: .cliAccountSyncedAt)
        try c.encodeIfPresent(customKeychainServiceName, forKey: .customKeychainServiceName)
        try c.encodeIfPresent(oauthAccountJSON, forKey: .oauthAccountJSON)
        try c.encodeIfPresent(claudeUsage, forKey: .claudeUsage)
        try c.encodeIfPresent(apiUsage, forKey: .apiUsage)
        try c.encode(iconConfig, forKey: .iconConfig)
        try c.encode(refreshInterval, forKey: .refreshInterval)
        try c.encode(autoStartSessionEnabled, forKey: .autoStartSessionEnabled)
        try c.encode(checkOverageLimitEnabled, forKey: .checkOverageLimitEnabled)
        try c.encodeIfPresent(monthlySpendLimitCents, forKey: .monthlySpendLimitCents)
        try c.encode(notificationSettings, forKey: .notificationSettings)
        try c.encode(isSelectedForDisplay, forKey: .isSelectedForDisplay)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastUsedAt, forKey: .lastUsedAt)
    }

    // MARK: - Computed Properties
    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    /// True if profile has credentials that can fetch usage data (Claude.ai, CLI OAuth, or API Console)
    /// Note: System keychain fallback is handled in ClaudeAPIService.getAuthentication() during actual API calls
    var hasUsageCredentials: Bool {
        hasClaudeAI || hasAPIConsole || hasValidCLIOAuth
    }

    /// True if profile has CLI OAuth credentials that are not expired
    var hasValidCLIOAuth: Bool {
        guard let cliJSON = cliCredentialsJSON else { return false }
        return !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON)
    }

    var hasAnyCredentials: Bool {
        hasClaudeAI || hasAPIConsole || cliCredentialsJSON != nil || customKeychainServiceName != nil
    }
}

// MARK: - ProfileCredentials (for compatibility)
/// Simple struct for passing credentials around
struct ProfileCredentials {
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var apiSessionKeyExpiry: Date?
    var cliCredentialsJSON: String?

    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    var hasCLI: Bool {
        cliCredentialsJSON != nil
    }
}
