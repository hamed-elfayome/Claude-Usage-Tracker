import Foundation

/// Menu bar icon style options
enum MenuBarIconStyle: String, CaseIterable, Codable {
    case battery
    case progressBar
    case percentageOnly
    case icon
    case compact

    var displayName: String {
        switch self {
        case .battery:
            return "Battery (Classic)"
        case .progressBar:
            return "Progress Bar"
        case .percentageOnly:
            return "Percentage"
        case .icon:
            return "Icon with Bar"
        case .compact:
            return "Compact"
        }
    }

    var description: String {
        switch self {
        case .battery:
            return "Original battery-style bar with Claude text below"
        case .progressBar:
            return "Clean horizontal progress bar only"
        case .percentageOnly:
            return "Just the percentage in color-coded text"
        case .icon:
            return "Circular ring with progress indicator"
        case .compact:
            return "Minimalist dot indicator"
        }
    }
}

/// Manages shared data storage between app and widgets using App Groups
class DataStore: StorageProvider {
    static let shared = DataStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Public access to the UserDefaults instance for KVO
    var userDefaults: UserDefaults {
        return defaults
    }

    init() {
        // Use App Group for sharing data between app and widgets
        if let groupDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) {
            self.defaults = groupDefaults
        } else {
            // Fallback to standard UserDefaults if App Group not configured
            self.defaults = UserDefaults.standard
        }
    }

    // MARK: - Usage Data

    /// Saves usage data to shared storage
    func saveUsage(_ usage: ClaudeUsage) {
        do {
            let data = try encoder.encode(usage)
            defaults.set(data, forKey: Constants.UserDefaultsKeys.claudeUsageData)
            // Note: synchronize() is deprecated and unnecessary - UserDefaults auto-syncs
            LoggingService.shared.logStorageSave("claudeUsageData")
        } catch {
            LoggingService.shared.logStorageError("saveUsage", error: error)
        }
    }

    /// Loads usage data from shared storage
    func loadUsage() -> ClaudeUsage? {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.claudeUsageData) else {
            LoggingService.shared.logStorageLoad("claudeUsageData", success: false)
            return nil
        }

        do {
            let usage = try decoder.decode(ClaudeUsage.self, from: data)
            LoggingService.shared.logStorageLoad("claudeUsageData", success: true)
            return usage
        } catch {
            LoggingService.shared.logStorageError("loadUsage", error: error)
            return nil
        }
    }

    // MARK: - User Preferences

    /// Saves notification preferences
    func saveNotificationsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaultsKeys.notificationsEnabled)
    }

    /// Loads notification preferences
    func loadNotificationsEnabled() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.notificationsEnabled)
    }

    /// Saves refresh interval
    func saveRefreshInterval(_ interval: TimeInterval) {
        defaults.set(interval, forKey: Constants.UserDefaultsKeys.refreshInterval)
    }

    /// Loads refresh interval
    func loadRefreshInterval() -> TimeInterval {
        let interval = defaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        return interval > 0 ? interval : Constants.RefreshIntervals.menuBar
    }

    /// Saves auto-start session preference
    func saveAutoStartSessionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaultsKeys.autoStartSessionEnabled)
    }

    /// Loads auto-start session preference
    func loadAutoStartSessionEnabled() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.autoStartSessionEnabled)
    }

    /// Saves check overage limit preference
    func saveCheckOverageLimitEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "checkOverageLimitEnabled")
    }

    /// Loads check overage limit preference (defaults to true)
    func loadCheckOverageLimitEnabled() -> Bool {
        // If key doesn't exist, register default as true
        if defaults.object(forKey: "checkOverageLimitEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "checkOverageLimitEnabled")
    }

    // MARK: - Organization Settings

    /// Saves selected organization ID for personal usage tracking
    func saveOrganizationId(_ organizationId: String) {
        defaults.set(organizationId, forKey: "selectedOrganizationId")
        LoggingService.shared.logStorageSave("selectedOrganizationId")
    }

    /// Loads selected organization ID (returns nil if not set)
    func loadOrganizationId() -> String? {
        let orgId = defaults.string(forKey: "selectedOrganizationId")
        LoggingService.shared.logStorageLoad("selectedOrganizationId", success: orgId != nil)
        return orgId
    }

    /// Clears stored organization ID (call when session key changes)
    func clearOrganizationId() {
        defaults.removeObject(forKey: "selectedOrganizationId")
        LoggingService.shared.logInfo("Cleared stored organization ID")
    }

    // MARK: - Debug Settings

    /// Saves debug API logging preference
    func saveDebugAPILoggingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "debugAPILoggingEnabled")
    }

    /// Loads debug API logging preference (defaults to false)
    func loadDebugAPILoggingEnabled() -> Bool {
        return defaults.bool(forKey: "debugAPILoggingEnabled")
    }

    // MARK: - Statusline Configuration

    /// Saves statusline show directory preference
    func saveStatuslineShowDirectory(_ show: Bool) {
        defaults.set(show, forKey: Constants.UserDefaultsKeys.statuslineShowDirectory)
    }

    /// Loads statusline show directory preference (defaults to true)
    func loadStatuslineShowDirectory() -> Bool {
        if defaults.object(forKey: Constants.UserDefaultsKeys.statuslineShowDirectory) == nil {
            return true
        }
        return defaults.bool(forKey: Constants.UserDefaultsKeys.statuslineShowDirectory)
    }

    /// Saves statusline show branch preference
    func saveStatuslineShowBranch(_ show: Bool) {
        defaults.set(show, forKey: Constants.UserDefaultsKeys.statuslineShowBranch)
    }

    /// Loads statusline show branch preference (defaults to true)
    func loadStatuslineShowBranch() -> Bool {
        if defaults.object(forKey: Constants.UserDefaultsKeys.statuslineShowBranch) == nil {
            return true
        }
        return defaults.bool(forKey: Constants.UserDefaultsKeys.statuslineShowBranch)
    }

    /// Saves statusline show usage preference
    func saveStatuslineShowUsage(_ show: Bool) {
        defaults.set(show, forKey: Constants.UserDefaultsKeys.statuslineShowUsage)
    }

    /// Loads statusline show usage preference (defaults to true)
    func loadStatuslineShowUsage() -> Bool {
        if defaults.object(forKey: Constants.UserDefaultsKeys.statuslineShowUsage) == nil {
            return true
        }
        return defaults.bool(forKey: Constants.UserDefaultsKeys.statuslineShowUsage)
    }

    /// Saves statusline show progress bar preference
    func saveStatuslineShowProgressBar(_ show: Bool) {
        defaults.set(show, forKey: Constants.UserDefaultsKeys.statuslineShowProgressBar)
    }

    /// Loads statusline show progress bar preference (defaults to true)
    func loadStatuslineShowProgressBar() -> Bool {
        if defaults.object(forKey: Constants.UserDefaultsKeys.statuslineShowProgressBar) == nil {
            return true
        }
        return defaults.bool(forKey: Constants.UserDefaultsKeys.statuslineShowProgressBar)
    }

    // MARK: - Setup State

    /// Saves whether the user has completed the setup wizard
    func saveHasCompletedSetup(_ completed: Bool) {
        defaults.set(completed, forKey: "hasCompletedSetup")
    }

    /// Checks if the user has completed the setup wizard
    func hasCompletedSetup() -> Bool {
        // Check if flag is set
        if defaults.bool(forKey: "hasCompletedSetup") {
            return true
        }

        // Also check if session key file exists as fallback
        let sessionKeyPath = Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")

        if FileManager.default.fileExists(atPath: sessionKeyPath.path) {
            // Auto-mark as complete if session key exists
            saveHasCompletedSetup(true)
            return true
        }

        return false
    }

    // MARK: - GitHub Star Prompt Tracking

    /// Saves the first launch date
    func saveFirstLaunchDate(_ date: Date) {
        defaults.set(date, forKey: Constants.UserDefaultsKeys.firstLaunchDate)
    }

    /// Loads the first launch date
    func loadFirstLaunchDate() -> Date? {
        return defaults.object(forKey: Constants.UserDefaultsKeys.firstLaunchDate) as? Date
    }

    /// Saves the last GitHub star prompt date
    func saveLastGitHubStarPromptDate(_ date: Date) {
        defaults.set(date, forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate)
    }

    /// Loads the last GitHub star prompt date
    func loadLastGitHubStarPromptDate() -> Date? {
        return defaults.object(forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate) as? Date
    }

    /// Saves whether the user has starred the GitHub repository
    func saveHasStarredGitHub(_ starred: Bool) {
        defaults.set(starred, forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
    }

    /// Loads whether the user has starred the GitHub repository
    func loadHasStarredGitHub() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
    }

    /// Saves the user's preference to never show GitHub prompt
    func saveNeverShowGitHubPrompt(_ neverShow: Bool) {
        defaults.set(neverShow, forKey: Constants.UserDefaultsKeys.neverShowGitHubPrompt)
    }

    /// Loads the user's preference to never show GitHub prompt
    func loadNeverShowGitHubPrompt() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.neverShowGitHubPrompt)
    }

    /// Determines whether the GitHub star prompt should be shown
    /// Returns true if all conditions are met:
    /// - User hasn't opted out with "Don't ask again"
    /// - User hasn't already starred the repo
    /// - Either: 1+ days since first launch (never shown before), OR 10+ days since last shown
    func shouldShowGitHubStarPrompt() -> Bool {
        // Don't show if user said "don't ask again"
        if loadNeverShowGitHubPrompt() {
            return false
        }

        // Don't show if user already starred
        if loadHasStarredGitHub() {
            return false
        }

        let now = Date()

        // Check if we have a first launch date
        guard let firstLaunch = loadFirstLaunchDate() else {
            // If no first launch date, save it now and don't show prompt yet
            saveFirstLaunchDate(now)
            return false
        }

        // Check if it's been at least 1 day since first launch
        let timeSinceFirstLaunch = now.timeIntervalSince(firstLaunch)
        if timeSinceFirstLaunch < Constants.GitHubPromptTiming.initialDelay {
            return false
        }

        // Check if we've ever shown the prompt before
        guard let lastPrompt = loadLastGitHubStarPromptDate() else {
            // Never shown before, and it's been 1+ days since first launch
            return true
        }

        // Has been shown before - check if enough time has passed for a reminder
        let timeSinceLastPrompt = now.timeIntervalSince(lastPrompt)
        return timeSinceLastPrompt >= Constants.GitHubPromptTiming.reminderInterval
    }

    // MARK: - API Usage Tracking

    /// Saves API usage data to shared storage
    func saveAPIUsage(_ usage: APIUsage) {
        do {
            let data = try encoder.encode(usage)
            defaults.set(data, forKey: Constants.UserDefaultsKeys.apiUsageData)
        } catch {
            // Silently handle encoding errors
        }
    }

    /// Loads API usage data from shared storage
    func loadAPIUsage() -> APIUsage? {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.apiUsageData) else {
            return nil
        }

        do {
            return try decoder.decode(APIUsage.self, from: data)
        } catch {
            // Silently handle decoding errors
            return nil
        }
    }

    /// Saves API tracking enabled preference
    func saveAPITrackingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaultsKeys.apiTrackingEnabled)
    }

    /// Loads API tracking enabled preference
    func loadAPITrackingEnabled() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.apiTrackingEnabled)
    }

    /// Saves API session key to Keychain
    func saveAPISessionKey(_ key: String) {
        do {
            try KeychainService.shared.save(key, for: .apiSessionKey)

            // Migration: Remove from UserDefaults if it exists there
            if defaults.string(forKey: Constants.UserDefaultsKeys.apiSessionKey) != nil {
                defaults.removeObject(forKey: Constants.UserDefaultsKeys.apiSessionKey)
                LoggingService.shared.log("Migrated API session key from UserDefaults to Keychain")
            }
        } catch {
            LoggingService.shared.logStorageError("saveAPISessionKey", error: error)
        }
    }

    /// Loads API session key from Keychain (with fallback to UserDefaults for migration)
    func loadAPISessionKey() -> String? {
        do {
            // Try to load from Keychain first
            if let key = try KeychainService.shared.load(for: .apiSessionKey) {
                return key
            }

            // Migration: Check UserDefaults for existing key
            if let legacyKey = defaults.string(forKey: Constants.UserDefaultsKeys.apiSessionKey) {
                LoggingService.shared.log("Found API session key in UserDefaults, migrating to Keychain")
                // Migrate to Keychain
                try KeychainService.shared.save(legacyKey, for: .apiSessionKey)
                // Remove from UserDefaults
                defaults.removeObject(forKey: Constants.UserDefaultsKeys.apiSessionKey)
                return legacyKey
            }

            return nil
        } catch {
            LoggingService.shared.logStorageError("loadAPISessionKey", error: error)
            // Fallback to UserDefaults on error
            return defaults.string(forKey: Constants.UserDefaultsKeys.apiSessionKey)
        }
    }

    /// Saves selected API organization ID
    func saveAPIOrganizationId(_ orgId: String) {
        defaults.set(orgId, forKey: Constants.UserDefaultsKeys.apiOrganizationId)
    }

    /// Loads selected API organization ID
    func loadAPIOrganizationId() -> String? {
        return defaults.string(forKey: Constants.UserDefaultsKeys.apiOrganizationId)
    }

    // MARK: - Menu Bar Icon Style

    /// Saves menu bar icon style preference
    func saveMenuBarIconStyle(_ style: MenuBarIconStyle) {
        defaults.set(style.rawValue, forKey: Constants.UserDefaultsKeys.menuBarIconStyle)
    }

    /// Loads menu bar icon style preference (defaults to battery)
    func loadMenuBarIconStyle() -> MenuBarIconStyle {
        guard let rawValue = defaults.string(forKey: Constants.UserDefaultsKeys.menuBarIconStyle),
              let style = MenuBarIconStyle(rawValue: rawValue) else {
            return .battery
        }
        return style
    }

    /// Saves monochrome mode preference
    func saveMonochromeMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaultsKeys.monochromeMode)
    }

    /// Loads monochrome mode preference (defaults to false)
    func loadMonochromeMode() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.monochromeMode)
    }

    // MARK: - Menu Bar Icon Configuration (Multi-Metric System)

    /// Saves complete menu bar icon configuration
    func saveMenuBarIconConfiguration(_ config: MenuBarIconConfiguration) {
        do {
            let data = try encoder.encode(config)
            defaults.set(data, forKey: Constants.UserDefaultsKeys.menuBarIconConfiguration)
        } catch {
            LoggingService.shared.logStorageError("saveMenuBarIconConfiguration", error: error)
        }
    }

    /// Loads complete menu bar icon configuration
    func loadMenuBarIconConfiguration() -> MenuBarIconConfiguration {
        // Try to load new configuration format
        if let data = defaults.data(forKey: Constants.UserDefaultsKeys.menuBarIconConfiguration) {
            do {
                let config = try decoder.decode(MenuBarIconConfiguration.self, from: data)
                return config
            } catch {
                LoggingService.shared.logStorageError("loadMenuBarIconConfiguration", error: error)
            }
        }

        // Migrate from legacy settings if they exist
        return migrateFromLegacySettings()
    }

    /// Migrates from legacy single-icon settings to new multi-metric system
    private func migrateFromLegacySettings() -> MenuBarIconConfiguration {
        var config = MenuBarIconConfiguration.default

        // Migrate monochrome mode
        config.monochromeMode = loadMonochromeMode()

        // Migrate icon style for session (was the only option before)
        let legacyStyle = loadMenuBarIconStyle()
        if var sessionConfig = config.config(for: .session) {
            sessionConfig.iconStyle = legacyStyle
            sessionConfig.isEnabled = true  // Session was always enabled before
            config.updateConfig(sessionConfig)
        }

        // Save migrated config
        saveMenuBarIconConfiguration(config)

        return config
    }

    /// Saves show icon names preference
    func saveShowIconNames(_ show: Bool) {
        defaults.set(show, forKey: Constants.UserDefaultsKeys.showIconNames)
    }

    /// Loads show icon names preference (defaults to true)
    func loadShowIconNames() -> Bool {
        if defaults.object(forKey: Constants.UserDefaultsKeys.showIconNames) == nil {
            return true
        }
        return defaults.bool(forKey: Constants.UserDefaultsKeys.showIconNames)
    }

    // MARK: - Per-Metric Configuration Helpers

    /// Updates configuration for a specific metric
    func updateMetricConfig(_ metricConfig: MetricIconConfig) {
        var fullConfig = loadMenuBarIconConfiguration()
        fullConfig.updateConfig(metricConfig)
        saveMenuBarIconConfiguration(fullConfig)
    }

    /// Gets configuration for a specific metric type
    func loadMetricConfig(for metricType: MenuBarMetricType) -> MetricIconConfig? {
        let config = loadMenuBarIconConfiguration()
        return config.config(for: metricType)
    }

    /// Toggles a metric on/off
    func setMetricEnabled(_ metricType: MenuBarMetricType, enabled: Bool) {
        var config = loadMenuBarIconConfiguration()
        if var metricConfig = config.config(for: metricType) {
            metricConfig.isEnabled = enabled
            config.updateConfig(metricConfig)
            saveMenuBarIconConfiguration(config)
        }
    }

    /// Updates metric order (for drag-to-reorder)
    func updateMetricOrder(metricType: MenuBarMetricType, order: Int) {
        var config = loadMenuBarIconConfiguration()
        if var metricConfig = config.config(for: metricType) {
            metricConfig.order = order
            config.updateConfig(metricConfig)
            saveMenuBarIconConfiguration(config)
        }
    }

    /// Updates icon style for a specific metric
    func updateMetricIconStyle(metricType: MenuBarMetricType, style: MenuBarIconStyle) {
        var config = loadMenuBarIconConfiguration()
        if var metricConfig = config.config(for: metricType) {
            metricConfig.iconStyle = style
            config.updateConfig(metricConfig)
            saveMenuBarIconConfiguration(config)
        }
    }

    /// Updates week display mode
    func updateWeekDisplayMode(_ mode: WeekDisplayMode) {
        var config = loadMenuBarIconConfiguration()
        if var weekConfig = config.config(for: .week) {
            weekConfig.weekDisplayMode = mode
            config.updateConfig(weekConfig)
            saveMenuBarIconConfiguration(config)
        }
    }

    /// Updates API display mode
    func updateAPIDisplayMode(_ mode: APIDisplayMode) {
        var config = loadMenuBarIconConfiguration()
        if var apiConfig = config.config(for: .api) {
            apiConfig.apiDisplayMode = mode
            config.updateConfig(apiConfig)
            saveMenuBarIconConfiguration(config)
        }
    }

    // MARK: - Testing Helpers

    /// Resets all GitHub star prompt tracking (for testing purposes)
    func resetGitHubStarPromptForTesting() {
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.firstLaunchDate)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.neverShowGitHubPrompt)
    }
}
