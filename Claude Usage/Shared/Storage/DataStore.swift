import Foundation

/// Manages shared data storage between app and widgets using App Groups
class DataStore {
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
            defaults.synchronize()
        } catch {
            // Silently handle encoding errors
        }
    }

    /// Loads usage data from shared storage
    func loadUsage() -> ClaudeUsage? {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.claudeUsageData) else {
            return nil
        }

        do {
            return try decoder.decode(ClaudeUsage.self, from: data)
        } catch {
            // Silently handle decoding errors
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
        defaults.synchronize()
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
        defaults.synchronize()
    }

    /// Loads the first launch date
    func loadFirstLaunchDate() -> Date? {
        return defaults.object(forKey: Constants.UserDefaultsKeys.firstLaunchDate) as? Date
    }

    /// Saves the last GitHub star prompt date
    func saveLastGitHubStarPromptDate(_ date: Date) {
        defaults.set(date, forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate)
        defaults.synchronize()
    }

    /// Loads the last GitHub star prompt date
    func loadLastGitHubStarPromptDate() -> Date? {
        return defaults.object(forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate) as? Date
    }

    /// Saves whether the user has starred the GitHub repository
    func saveHasStarredGitHub(_ starred: Bool) {
        defaults.set(starred, forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
        defaults.synchronize()
    }

    /// Loads whether the user has starred the GitHub repository
    func loadHasStarredGitHub() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
    }

    /// Saves the user's preference to never show GitHub prompt
    func saveNeverShowGitHubPrompt(_ neverShow: Bool) {
        defaults.set(neverShow, forKey: Constants.UserDefaultsKeys.neverShowGitHubPrompt)
        defaults.synchronize()
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
            defaults.synchronize()
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
        defaults.synchronize()
    }

    /// Loads API tracking enabled preference
    func loadAPITrackingEnabled() -> Bool {
        return defaults.bool(forKey: Constants.UserDefaultsKeys.apiTrackingEnabled)
    }

    /// Saves API session key
    func saveAPISessionKey(_ key: String) {
        defaults.set(key, forKey: Constants.UserDefaultsKeys.apiSessionKey)
        defaults.synchronize()
    }

    /// Loads API session key
    func loadAPISessionKey() -> String? {
        return defaults.string(forKey: Constants.UserDefaultsKeys.apiSessionKey)
    }

    /// Saves selected API organization ID
    func saveAPIOrganizationId(_ orgId: String) {
        defaults.set(orgId, forKey: Constants.UserDefaultsKeys.apiOrganizationId)
        defaults.synchronize()
    }

    /// Loads selected API organization ID
    func loadAPIOrganizationId() -> String? {
        return defaults.string(forKey: Constants.UserDefaultsKeys.apiOrganizationId)
    }

    // MARK: - Testing Helpers

    /// Resets all GitHub star prompt tracking (for testing purposes)
    func resetGitHubStarPromptForTesting() {
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.firstLaunchDate)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.lastGitHubStarPromptDate)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.hasStarredGitHub)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.neverShowGitHubPrompt)
        defaults.synchronize()
    }
}
