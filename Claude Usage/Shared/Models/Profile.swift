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
    var cliCredentialsJSON: String?

    // MARK: - CLI Account Sync Metadata
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    // MARK: - Usage Data (Per-Profile)
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?

    // MARK: - Appearance Settings (Per-Profile)
    var iconConfig: MenuBarIconConfiguration

    // MARK: - Account Tier (cached from organization capabilities)
    var accountTier: AccountTier?

    // MARK: - Behavior Settings (Per-Profile)
    var refreshInterval: TimeInterval
    var autoStartSessionEnabled: Bool
    var checkOverageLimitEnabled: Bool
    var autoRotateEnabled: Bool

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
        cliCredentialsJSON: String? = nil,
        hasCliAccount: Bool = false,
        cliAccountSyncedAt: Date? = nil,
        claudeUsage: ClaudeUsage? = nil,
        apiUsage: APIUsage? = nil,
        accountTier: AccountTier? = nil,
        iconConfig: MenuBarIconConfiguration = .default,
        refreshInterval: TimeInterval = 30.0,
        autoStartSessionEnabled: Bool = false,
        checkOverageLimitEnabled: Bool = true,
        autoRotateEnabled: Bool = false,
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
        self.cliCredentialsJSON = cliCredentialsJSON
        self.hasCliAccount = hasCliAccount
        self.cliAccountSyncedAt = cliAccountSyncedAt
        self.claudeUsage = claudeUsage
        self.apiUsage = apiUsage
        self.accountTier = accountTier
        self.iconConfig = iconConfig
        self.refreshInterval = refreshInterval
        self.autoStartSessionEnabled = autoStartSessionEnabled
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.autoRotateEnabled = autoRotateEnabled
        self.notificationSettings = notificationSettings
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Codable (backward compatibility for new fields)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        claudeSessionKey = try container.decodeIfPresent(String.self, forKey: .claudeSessionKey)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        apiSessionKey = try container.decodeIfPresent(String.self, forKey: .apiSessionKey)
        apiOrganizationId = try container.decodeIfPresent(String.self, forKey: .apiOrganizationId)
        cliCredentialsJSON = try container.decodeIfPresent(String.self, forKey: .cliCredentialsJSON)
        hasCliAccount = try container.decode(Bool.self, forKey: .hasCliAccount)
        cliAccountSyncedAt = try container.decodeIfPresent(Date.self, forKey: .cliAccountSyncedAt)
        claudeUsage = try container.decodeIfPresent(ClaudeUsage.self, forKey: .claudeUsage)
        apiUsage = try container.decodeIfPresent(APIUsage.self, forKey: .apiUsage)
        accountTier = try? container.decodeIfPresent(AccountTier.self, forKey: .accountTier)
        iconConfig = try container.decode(MenuBarIconConfiguration.self, forKey: .iconConfig)
        refreshInterval = try container.decode(TimeInterval.self, forKey: .refreshInterval)
        autoStartSessionEnabled = try container.decode(Bool.self, forKey: .autoStartSessionEnabled)
        checkOverageLimitEnabled = try container.decode(Bool.self, forKey: .checkOverageLimitEnabled)
        autoRotateEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRotateEnabled) ?? false
        notificationSettings = try container.decode(NotificationSettings.self, forKey: .notificationSettings)
        isSelectedForDisplay = try container.decode(Bool.self, forKey: .isSelectedForDisplay)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decode(Date.self, forKey: .lastUsedAt)
    }

    // MARK: - Computed Properties
    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    /// True if profile has credentials that can fetch usage data (Claude.ai, CLI OAuth, or API Console)
    var hasUsageCredentials: Bool {
        hasClaudeAI || hasAPIConsole || hasValidCLIOAuth || hasValidSystemCLIOAuth
    }

    /// True if profile has CLI OAuth credentials that are not expired
    var hasValidCLIOAuth: Bool {
        guard let cliJSON = cliCredentialsJSON else { return false }
        // Check if not expired
        return !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON)
    }

    /// True if system Keychain has valid CLI OAuth credentials (fallback)
    var hasValidSystemCLIOAuth: Bool {
        guard let systemCredentials = try? ClaudeCodeSyncService.shared.readSystemCredentials() else {
            return false
        }
        // Check if not expired and has valid access token
        return !ClaudeCodeSyncService.shared.isTokenExpired(systemCredentials) &&
               ClaudeCodeSyncService.shared.extractAccessToken(from: systemCredentials) != nil
    }

    var hasAnyCredentials: Bool {
        hasClaudeAI || hasAPIConsole || cliCredentialsJSON != nil
    }

    /// True if profile can provide session usage data (required for auto-rotation)
    var hasSessionCredentials: Bool {
        hasClaudeAI || hasValidCLIOAuth || hasValidSystemCLIOAuth
    }
}

// MARK: - ProfileCredentials (for compatibility)
/// Simple struct for passing credentials around
struct ProfileCredentials {
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
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
