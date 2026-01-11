//
//  LocalizationManager.swift
//  Claude Usage - Centralized Localization System
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation

/// Extension for easy string localization
extension String {
    /// Returns localized string
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }

    /// Returns localized string with format arguments
    func localized(with args: CVarArg...) -> String {
        return String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }

    /// Returns localized string with comment
    func localized(comment: String) -> String {
        return NSLocalizedString(self, comment: comment)
    }
}

/// Type-safe localization keys (optional but recommended)
enum LocalizationKey: String {

    // MARK: - Common
    case appName = "app.name"
    case ok = "common.ok"
    case cancel = "common.cancel"
    case save = "common.save"
    case delete = "common.delete"
    case done = "common.done"
    case close = "common.close"
    case refresh = "common.refresh"
    case settings = "common.settings"
    case quit = "common.quit"
    case validate = "common.validate"
    case yes = "common.yes"
    case no = "common.no"

    // MARK: - Settings Sections
    case settingsTitle = "settings.title"
    case personalUsage = "settings.personal_usage"
    case personalUsageDesc = "settings.personal_usage.description"
    case apiBilling = "settings.api_billing"
    case apiBillingDesc = "settings.api_billing.description"
    case general = "settings.general"
    case generalDesc = "settings.general.description"
    case appearance = "settings.appearance"
    case appearanceDesc = "settings.appearance.description"
    case sessionManagement = "settings.session_management"
    case sessionManagementDesc = "settings.session_management.description"
    case notifications = "settings.notifications"
    case notificationsDesc = "settings.notifications.description"
    case claudeCLI = "settings.claude_cli"
    case claudeCLIDesc = "settings.claude_cli.description"
    case about = "settings.about"
    case aboutDesc = "settings.about.description"

    // MARK: - Menu Bar
    case claudeUsage = "menubar.claude_usage"
    case sessionUsage = "menubar.session_usage"
    case weeklyUsage = "menubar.weekly_usage"
    case opusUsage = "menubar.opus_usage"
    case apiCredits = "menubar.api_credits"
    case resetsTime = "menubar.resets_time"

    // MARK: - General Settings
    case launchAtLogin = "general.launch_at_login"
    case launchAtLoginDesc = "general.launch_at_login.description"
    case refreshInterval = "general.refresh_interval"
    case refreshIntervalDesc = "general.refresh_interval.description"
    case checkOverageLimit = "general.check_overage_limit"
    case checkOverageLimitDesc = "general.check_overage_limit.description"
    case languageTitle = "general.language.title"
    case languageSelect = "general.language.select"
    case languageRestartNote = "general.language.restart_note"

    // MARK: - Notifications
    case enableNotifications = "notifications.enable"
    case enableNotificationsDesc = "notifications.enable.description"
    case alertThresholds = "notifications.alert_thresholds"
    case thresholdWarning = "notifications.threshold.warning"
    case thresholdHigh = "notifications.threshold.high"
    case thresholdCritical = "notifications.threshold.critical"
    case thresholdSessionReset = "notifications.threshold.session_reset"

    // MARK: - Setup Wizard
    case welcomeTitle = "setup.welcome.title"
    case welcomeSubtitle = "setup.welcome.subtitle"
    case stepGetSessionKey = "setup.step.get_session_key"
    case stepEnterSessionKey = "setup.step.enter_session_key"
    case openClaudeAI = "setup.open_claude_ai"
    case showInstructions = "setup.show_instructions"
    case hideInstructions = "setup.hide_instructions"
    case instructionStep1 = "setup.instruction.step1"
    case instructionStep2 = "setup.instruction.step2"
    case instructionStep3 = "setup.instruction.step3"
    case instructionStep4 = "setup.instruction.step4"
    case pasteSessionKey = "setup.paste_session_key"
    case autoStartSession = "setup.auto_start_session"
    case autoStartSessionDesc = "setup.auto_start_session.description"
    case enableAutoStart = "setup.enable_auto_start"
    case menuBarAppearance = "setup.menubar_appearance"
    case chooseIconStyle = "setup.choose_icon_style"
    case monochromeAdaptive = "setup.monochrome_adaptive"
    case validationSuccess = "setup.validation.success"

    // MARK: - About
    case createdBy = "about.created_by"
    case contributors = "about.contributors"
    case links = "about.links"
    case starOnGitHub = "about.star_github"
    case reportIssue = "about.report_issue"
    case sendFeedback = "about.send_feedback"
    case mitLicense = "about.mit_license"
    case copyright = "about.copyright"

    // MARK: - Notification Messages
    case notifSessionWarningTitle = "notification.session_warning.title"
    case notifSessionWarningMessage = "notification.session_warning.message"
    case notifSessionCriticalTitle = "notification.session_critical.title"
    case notifSessionCriticalMessage = "notification.session_critical.message"
    case notifSessionResetTitle = "notification.session_reset.title"
    case notifSessionResetMessage = "notification.session_reset.message"
    case notifSessionAutoStartedTitle = "notification.session_auto_started.title"
    case notifSessionAutoStartedMessage = "notification.session_auto_started.message"
    case notifWeeklyWarningTitle = "notification.weekly_warning.title"
    case notifWeeklyWarningMessage = "notification.weekly_warning.message"
    case notifWeeklyCriticalTitle = "notification.weekly_critical.title"
    case notifWeeklyCriticalMessage = "notification.weekly_critical.message"
    case notifOpusWarningTitle = "notification.opus_warning.title"
    case notifOpusWarningMessage = "notification.opus_warning.message"
    case notifOpusCriticalTitle = "notification.opus_critical.title"
    case notifOpusCriticalMessage = "notification.opus_critical.message"
    case notifEnabledTitle = "notification.enabled.title"
    case notifEnabledMessage = "notification.enabled.message"

    // MARK: - Wizard Steps
    case wizardEnterKey = "wizard.enter_key"
    case wizardSelectOrg = "wizard.select_org"
    case wizardConfirm = "wizard.confirm"
    case wizardTesting = "wizard.testing"
    case wizardTestConnection = "wizard.test_connection"
    case wizardFetching = "wizard.fetching"
    case wizardFetchOrganizations = "wizard.fetch_organizations"
    case wizardSaving = "wizard.saving"
    case wizardSaveConfiguration = "wizard.save_configuration"

    // MARK: - CLI Account
    case cliTitle = "cli.title"
    case cliSubtitle = "cli.subtitle"
    case cliSynced = "cli.synced"
    case cliNotSynced = "cli.not_synced"
    case cliAccountDetails = "cli.account_details"
    case cliCredentialsSynced = "cli.credentials_synced"
    case cliNoCredentials = "cli.no_credentials"
    case cliResync = "cli.resync"
    case cliSyncFromCode = "cli.sync_from_code"
    case cliBenefit1 = "cli.benefit_1"
    case cliBenefit2 = "cli.benefit_2"
    case cliBenefit3 = "cli.benefit_3"

    /// Localized value
    var localized: String {
        return rawValue.localized
    }

    /// Localized value with format arguments
    func localized(_ args: CVarArg...) -> String {
        return String(format: rawValue.localized, arguments: args)
    }
}
