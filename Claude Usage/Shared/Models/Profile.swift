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

    // MARK: - Usage Data (Per-Profile)
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?

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

    // MARK: - Provider Type (NEW)
    var providerType: ProfileProviderType
    var primaryModel: String?

    // MARK: - OpenAI Credentials (NEW)
    var openaiAdminKey: String?
    var openaiApiKey: String?
    var openaiOrganizationId: String?

    // MARK: - OpenAI Usage Data (NEW)
    var openaiUsage: OpenAIUsage?
    var codexUsage: CodexUsage?

    // MARK: - Budget Settings (NEW)
    var spendBudgetCents: Int?
    var spendBudgetCurrency: String?

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
        claudeUsage: ClaudeUsage? = nil,
        apiUsage: APIUsage? = nil,
        iconConfig: MenuBarIconConfiguration = .default,
        refreshInterval: TimeInterval = 30.0,
        autoStartSessionEnabled: Bool = false,
        checkOverageLimitEnabled: Bool = true,
        notificationSettings: NotificationSettings = NotificationSettings(),
        isSelectedForDisplay: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        providerType: ProfileProviderType = .claudeMax,
        primaryModel: String? = nil,
        openaiAdminKey: String? = nil,
        openaiApiKey: String? = nil,
        openaiOrganizationId: String? = nil,
        openaiUsage: OpenAIUsage? = nil,
        codexUsage: CodexUsage? = nil,
        spendBudgetCents: Int? = nil,
        spendBudgetCurrency: String? = nil
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
        self.claudeUsage = claudeUsage
        self.apiUsage = apiUsage
        self.iconConfig = iconConfig
        self.refreshInterval = refreshInterval
        self.autoStartSessionEnabled = autoStartSessionEnabled
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.notificationSettings = notificationSettings
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.providerType = providerType
        self.primaryModel = primaryModel
        self.openaiAdminKey = openaiAdminKey
        self.openaiApiKey = openaiApiKey
        self.openaiOrganizationId = openaiOrganizationId
        self.openaiUsage = openaiUsage
        self.codexUsage = codexUsage
        self.spendBudgetCents = spendBudgetCents
        self.spendBudgetCurrency = spendBudgetCurrency
    }

    // MARK: - Backward-Compatible Decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        claudeSessionKey = try container.decodeIfPresent(String.self, forKey: .claudeSessionKey)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        apiSessionKey = try container.decodeIfPresent(String.self, forKey: .apiSessionKey)
        apiOrganizationId = try container.decodeIfPresent(String.self, forKey: .apiOrganizationId)
        apiSessionKeyExpiry = try container.decodeIfPresent(Date.self, forKey: .apiSessionKeyExpiry)
        cliCredentialsJSON = try container.decodeIfPresent(String.self, forKey: .cliCredentialsJSON)
        hasCliAccount = try container.decodeIfPresent(Bool.self, forKey: .hasCliAccount) ?? false
        cliAccountSyncedAt = try container.decodeIfPresent(Date.self, forKey: .cliAccountSyncedAt)
        claudeUsage = try container.decodeIfPresent(ClaudeUsage.self, forKey: .claudeUsage)
        apiUsage = try container.decodeIfPresent(APIUsage.self, forKey: .apiUsage)
        iconConfig = try container.decodeIfPresent(MenuBarIconConfiguration.self, forKey: .iconConfig) ?? .default
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 30.0
        autoStartSessionEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartSessionEnabled) ?? false
        checkOverageLimitEnabled = try container.decodeIfPresent(Bool.self, forKey: .checkOverageLimitEnabled) ?? true
        notificationSettings = try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings) ?? NotificationSettings()
        isSelectedForDisplay = try container.decodeIfPresent(Bool.self, forKey: .isSelectedForDisplay) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()

        // New fields — default gracefully when absent
        providerType = try container.decodeIfPresent(ProfileProviderType.self, forKey: .providerType) ?? .claudeMax
        primaryModel = try container.decodeIfPresent(String.self, forKey: .primaryModel)
        openaiAdminKey = try container.decodeIfPresent(String.self, forKey: .openaiAdminKey)
        openaiApiKey = try container.decodeIfPresent(String.self, forKey: .openaiApiKey)
        openaiOrganizationId = try container.decodeIfPresent(String.self, forKey: .openaiOrganizationId)
        openaiUsage = try container.decodeIfPresent(OpenAIUsage.self, forKey: .openaiUsage)
        codexUsage = try container.decodeIfPresent(CodexUsage.self, forKey: .codexUsage)
        spendBudgetCents = try container.decodeIfPresent(Int.self, forKey: .spendBudgetCents)
        spendBudgetCurrency = try container.decodeIfPresent(String.self, forKey: .spendBudgetCurrency)
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
        hasClaudeAI || hasAPIConsole || cliCredentialsJSON != nil
    }

    var hasOpenAIAPI: Bool {
        openaiAdminKey != nil
    }

    var hasCodexProbe: Bool {
        openaiApiKey != nil
    }

    /// The percentage to use for status bar threshold comparisons
    var effectivePercentageForThreshold: Double? {
        switch providerType {
        case .claudeMax:
            if primaryModel == "sonnet" {
                return claudeUsage?.sonnetWeeklyPercentage
            }
            return claudeUsage?.opusWeeklyPercentage ?? claudeUsage?.effectiveSessionPercentage
        case .codex:
            return codexUsage?.requestPercentageUsed
        case .claudeAPI:
            guard let budget = spendBudgetCents, budget > 0, let usage = apiUsage else { return nil }
            return Double(usage.currentSpendCents) / Double(budget) * 100.0
        case .openaiAPI:
            guard let budget = spendBudgetCents, budget > 0, let usage = openaiUsage else { return nil }
            return Double(usage.currentSpendCents) / Double(budget) * 100.0
        }
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
