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

    // Platform API credentials (platform.claude.com - for Claude Code team metrics)
    var apiSessionKey: String?
    var apiOrganizationId: String?

    // Console API credentials (console.anthropic.com - for billing/credits tracking)
    var consoleSessionKey: String?
    var consoleOrganizationId: String?

    var cliCredentialsJSON: String?

    // MARK: - CLI Account Sync Metadata
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    // MARK: - Usage Data (Per-Profile)
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?
    var claudeCodeMetrics: ClaudeCodeMetrics?

    // MARK: - Claude Code Team Settings
    var claudeCodeUserEmail: String?  // Email to identify user in team metrics
    var claudeCodeWorkspaceId: String?  // Workspace ID for usage_cost API
    var claudeCodeApiKeyId: String?  // API key ID to filter personal data

    // MARK: - Budget Settings
    var monthlyBudget: Double?  // Monthly spending budget in USD
    var budgetAlertThresholds: [Double]  // Alert thresholds (e.g., [50, 75, 90])
    var budgetAlertsEnabled: Bool  // Whether budget alerts are enabled

    // MARK: - Appearance Settings (Per-Profile)
    var iconConfig: MenuBarIconConfiguration

    // MARK: - Behavior Settings (Per-Profile)
    var refreshInterval: TimeInterval
    var autoStartSessionEnabled: Bool
    var checkOverageLimitEnabled: Bool

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
        consoleSessionKey: String? = nil,
        consoleOrganizationId: String? = nil,
        cliCredentialsJSON: String? = nil,
        hasCliAccount: Bool = false,
        cliAccountSyncedAt: Date? = nil,
        claudeUsage: ClaudeUsage? = nil,
        apiUsage: APIUsage? = nil,
        claudeCodeMetrics: ClaudeCodeMetrics? = nil,
        claudeCodeUserEmail: String? = nil,
        claudeCodeWorkspaceId: String? = nil,
        claudeCodeApiKeyId: String? = nil,
        monthlyBudget: Double? = nil,
        budgetAlertThresholds: [Double] = [50, 75, 90],
        budgetAlertsEnabled: Bool = false,
        iconConfig: MenuBarIconConfiguration = .default,
        refreshInterval: TimeInterval = 30.0,
        autoStartSessionEnabled: Bool = false,
        checkOverageLimitEnabled: Bool = true,
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
        self.consoleSessionKey = consoleSessionKey
        self.consoleOrganizationId = consoleOrganizationId
        self.cliCredentialsJSON = cliCredentialsJSON
        self.hasCliAccount = hasCliAccount
        self.cliAccountSyncedAt = cliAccountSyncedAt
        self.claudeUsage = claudeUsage
        self.apiUsage = apiUsage
        self.claudeCodeMetrics = claudeCodeMetrics
        self.claudeCodeUserEmail = claudeCodeUserEmail
        self.claudeCodeWorkspaceId = claudeCodeWorkspaceId
        self.claudeCodeApiKeyId = claudeCodeApiKeyId
        self.monthlyBudget = monthlyBudget
        self.budgetAlertThresholds = budgetAlertThresholds
        self.budgetAlertsEnabled = budgetAlertsEnabled
        self.iconConfig = iconConfig
        self.refreshInterval = refreshInterval
        self.autoStartSessionEnabled = autoStartSessionEnabled
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.notificationSettings = notificationSettings
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Computed Properties
    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    /// True if profile has Platform API credentials (platform.claude.com - Claude Code metrics)
    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    /// True if profile has Console API credentials (console.anthropic.com - billing/credits)
    var hasConsoleAPI: Bool {
        consoleSessionKey != nil && consoleOrganizationId != nil
    }

    /// True if profile has credentials that can fetch usage data (Claude.ai, CLI OAuth, or API Console)
    var hasUsageCredentials: Bool {
        hasClaudeAI || hasAPIConsole || hasConsoleAPI || hasValidCLIOAuth || hasValidSystemCLIOAuth
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
        hasClaudeAI || hasAPIConsole || hasConsoleAPI || cliCredentialsJSON != nil
    }
}

// MARK: - ProfileCredentials (for compatibility)
/// Simple struct for passing credentials around
struct ProfileCredentials {
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var consoleSessionKey: String?
    var consoleOrganizationId: String?
    var cliCredentialsJSON: String?

    var hasClaudeAI: Bool {
        claudeSessionKey != nil && organizationId != nil
    }

    /// Platform API (platform.claude.com - Claude Code metrics)
    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    /// Console API (console.anthropic.com - billing/credits)
    var hasConsoleAPI: Bool {
        consoleSessionKey != nil && consoleOrganizationId != nil
    }

    var hasCLI: Bool {
        cliCredentialsJSON != nil
    }
}
