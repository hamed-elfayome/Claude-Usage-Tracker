//
//  SharedDataStore.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-10.
//

import Foundation

/// Manages app-wide settings that are shared across all profiles
class SharedDataStore {
    static let shared = SharedDataStore()

    private let defaults: UserDefaults

    private enum Keys {
        // Language & Localization
        static let languageCode = "selectedLanguageCode"

        // Statusline Configuration
        static let statuslineShowDirectory = "statuslineShowDirectory"
        static let statuslineShowBranch = "statuslineShowBranch"
        static let statuslineShowUsage = "statuslineShowUsage"
        static let statuslineShowProgressBar = "statuslineShowProgressBar"
        static let statuslineShowResetTime = "statuslineShowResetTime"

        // Setup State
        static let hasCompletedSetup = "hasCompletedSetup"
        static let hasShownWizardOnce = "hasShownWizardOnce"

        // Debug Settings
        static let debugAPILoggingEnabled = "debugAPILoggingEnabled"
    }

    init() {
        // Use standard UserDefaults (app container)
        self.defaults = UserDefaults.standard
        LoggingService.shared.log("SharedDataStore: Using standard app container storage")
    }

    // MARK: - Language & Localization

    func saveLanguageCode(_ code: String) {
        defaults.set(code, forKey: Keys.languageCode)
    }

    func loadLanguageCode() -> String? {
        return defaults.string(forKey: Keys.languageCode)
    }

    // MARK: - Statusline Configuration

    func saveStatuslineShowDirectory(_ show: Bool) {
        defaults.set(show, forKey: Keys.statuslineShowDirectory)
    }

    func loadStatuslineShowDirectory() -> Bool {
        if defaults.object(forKey: Keys.statuslineShowDirectory) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.statuslineShowDirectory)
    }

    func saveStatuslineShowBranch(_ show: Bool) {
        defaults.set(show, forKey: Keys.statuslineShowBranch)
    }

    func loadStatuslineShowBranch() -> Bool {
        if defaults.object(forKey: Keys.statuslineShowBranch) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.statuslineShowBranch)
    }

    func saveStatuslineShowUsage(_ show: Bool) {
        defaults.set(show, forKey: Keys.statuslineShowUsage)
    }

    func loadStatuslineShowUsage() -> Bool {
        if defaults.object(forKey: Keys.statuslineShowUsage) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.statuslineShowUsage)
    }

    func saveStatuslineShowProgressBar(_ show: Bool) {
        defaults.set(show, forKey: Keys.statuslineShowProgressBar)
    }

    func loadStatuslineShowProgressBar() -> Bool {
        if defaults.object(forKey: Keys.statuslineShowProgressBar) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.statuslineShowProgressBar)
    }

    func saveStatuslineShowResetTime(_ show: Bool) {
        defaults.set(show, forKey: Keys.statuslineShowResetTime)
    }

    func loadStatuslineShowResetTime() -> Bool {
        if defaults.object(forKey: Keys.statuslineShowResetTime) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.statuslineShowResetTime)
    }

    // MARK: - Setup State

    func saveHasCompletedSetup(_ completed: Bool) {
        defaults.set(completed, forKey: Keys.hasCompletedSetup)
    }

    func hasCompletedSetup() -> Bool {
        // Check if flag is set
        if defaults.bool(forKey: Keys.hasCompletedSetup) {
            return true
        }

        // Also check if session key file exists as fallback (legacy)
        let sessionKeyPath = Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")

        if FileManager.default.fileExists(atPath: sessionKeyPath.path) {
            // Auto-mark as complete if session key exists
            saveHasCompletedSetup(true)
            return true
        }

        return false
    }

    func hasShownWizardOnce() -> Bool {
        return defaults.bool(forKey: Keys.hasShownWizardOnce)
    }

    func markWizardShown() {
        defaults.set(true, forKey: Keys.hasShownWizardOnce)
    }

    // MARK: - Debug Settings

    func saveDebugAPILoggingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.debugAPILoggingEnabled)
    }

    func loadDebugAPILoggingEnabled() -> Bool {
        return defaults.bool(forKey: Keys.debugAPILoggingEnabled)
    }
}
