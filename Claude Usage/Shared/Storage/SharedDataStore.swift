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

        // GitHub Star Tracking
        static let firstLaunchDate = "firstLaunchDate"
        static let lastGitHubStarPromptDate = "lastGitHubStarPromptDate"
        static let hasStarredGitHub = "hasStarredGitHub"
        static let neverShowGitHubPrompt = "neverShowGitHubPrompt"

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

    // MARK: - GitHub Star Prompt Tracking

    func saveFirstLaunchDate(_ date: Date) {
        defaults.set(date, forKey: Keys.firstLaunchDate)
    }

    func loadFirstLaunchDate() -> Date? {
        return defaults.object(forKey: Keys.firstLaunchDate) as? Date
    }

    func saveLastGitHubStarPromptDate(_ date: Date) {
        defaults.set(date, forKey: Keys.lastGitHubStarPromptDate)
    }

    func loadLastGitHubStarPromptDate() -> Date? {
        return defaults.object(forKey: Keys.lastGitHubStarPromptDate) as? Date
    }

    func saveHasStarredGitHub(_ starred: Bool) {
        defaults.set(starred, forKey: Keys.hasStarredGitHub)
    }

    func loadHasStarredGitHub() -> Bool {
        return defaults.bool(forKey: Keys.hasStarredGitHub)
    }

    func saveNeverShowGitHubPrompt(_ neverShow: Bool) {
        defaults.set(neverShow, forKey: Keys.neverShowGitHubPrompt)
    }

    func loadNeverShowGitHubPrompt() -> Bool {
        return defaults.bool(forKey: Keys.neverShowGitHubPrompt)
    }

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

    // MARK: - Debug Settings

    func saveDebugAPILoggingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.debugAPILoggingEnabled)
    }

    func loadDebugAPILoggingEnabled() -> Bool {
        return defaults.bool(forKey: Keys.debugAPILoggingEnabled)
    }

    // MARK: - Testing Helpers

    func resetGitHubStarPromptForTesting() {
        defaults.removeObject(forKey: Keys.firstLaunchDate)
        defaults.removeObject(forKey: Keys.lastGitHubStarPromptDate)
        defaults.removeObject(forKey: Keys.hasStarredGitHub)
        defaults.removeObject(forKey: Keys.neverShowGitHubPrompt)
    }
}
