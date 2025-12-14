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
}
