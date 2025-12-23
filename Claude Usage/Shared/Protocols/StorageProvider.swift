//
//  StorageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

/// Protocol defining storage operations for the application
/// This enables dependency injection and testing with mock storage
protocol StorageProvider {
    // MARK: - Usage Data
    func saveUsage(_ usage: ClaudeUsage)
    func loadUsage() -> ClaudeUsage?

    // MARK: - API Usage Data
    func saveAPIUsage(_ usage: APIUsage)
    func loadAPIUsage() -> APIUsage?

    // MARK: - User Preferences
    func saveNotificationsEnabled(_ enabled: Bool)
    func loadNotificationsEnabled() -> Bool

    func saveRefreshInterval(_ interval: TimeInterval)
    func loadRefreshInterval() -> TimeInterval

    func saveAutoStartSessionEnabled(_ enabled: Bool)
    func loadAutoStartSessionEnabled() -> Bool

    func saveCheckOverageLimitEnabled(_ enabled: Bool)
    func loadCheckOverageLimitEnabled() -> Bool

    // MARK: - API Tracking
    func saveAPITrackingEnabled(_ enabled: Bool)
    func loadAPITrackingEnabled() -> Bool

    func saveAPISessionKey(_ key: String)
    func loadAPISessionKey() -> String?
    func deleteAPISessionKey()

    func saveAPIOrganizationId(_ orgId: String)
    func loadAPIOrganizationId() -> String?

    // MARK: - Statusline Configuration
    func saveStatuslineShowDirectory(_ show: Bool)
    func loadStatuslineShowDirectory() -> Bool

    func saveStatuslineShowBranch(_ show: Bool)
    func loadStatuslineShowBranch() -> Bool

    func saveStatuslineShowUsage(_ show: Bool)
    func loadStatuslineShowUsage() -> Bool

    func saveStatuslineShowProgressBar(_ show: Bool)
    func loadStatuslineShowProgressBar() -> Bool

    // MARK: - Setup State
    func saveHasCompletedSetup(_ completed: Bool)
    func hasCompletedSetup() -> Bool

    // MARK: - GitHub Star Prompt
    func saveFirstLaunchDate(_ date: Date)
    func loadFirstLaunchDate() -> Date?

    func saveLastGitHubStarPromptDate(_ date: Date)
    func loadLastGitHubStarPromptDate() -> Date?

    func saveHasStarredGitHub(_ starred: Bool)
    func loadHasStarredGitHub() -> Bool

    func saveNeverShowGitHubPrompt(_ neverShow: Bool)
    func loadNeverShowGitHubPrompt() -> Bool

    func shouldShowGitHubStarPrompt() -> Bool
}
