import Foundation

/// Application-wide constants
enum Constants {
    // App Group identifier for sharing data between app and widgets
    static let appGroupIdentifier = "group.com.claudeusagetracker.shared"

    // UserDefaults keys
    enum UserDefaultsKeys {
        static let claudeUsageData = "claudeUsageData"
        static let notificationsEnabled = "notificationsEnabled"
        static let refreshInterval = "refreshInterval"
        static let autoStartSessionEnabled = "autoStartSessionEnabled"

        // Statusline component configuration
        static let statuslineShowDirectory = "statuslineShowDirectory"
        static let statuslineShowBranch = "statuslineShowBranch"
        static let statuslineShowUsage = "statuslineShowUsage"
        static let statuslineShowProgressBar = "statuslineShowProgressBar"

        // GitHub star prompt tracking
        static let firstLaunchDate = "firstLaunchDate"
        static let lastGitHubStarPromptDate = "lastGitHubStarPromptDate"
        static let hasStarredGitHub = "hasStarredGitHub"
        static let neverShowGitHubPrompt = "neverShowGitHubPrompt"
    }

    // Claude Code paths
    enum ClaudePaths {
        /// Get the REAL user home directory (not sandboxed container)
        static var homeDirectory: URL {
            // Try to get real home from environment variable
            if let home = ProcessInfo.processInfo.environment["HOME"] {
                return URL(fileURLWithPath: home)
            }
            // Fallback to FileManager (might be sandboxed)
            return FileManager.default.homeDirectoryForCurrentUser
        }

        static var claudeDirectory: URL {
            homeDirectory.appendingPathComponent(".claude")
        }

        static var projectsDirectory: URL {
            claudeDirectory.appendingPathComponent("projects")
        }
    }

    // Refresh intervals (in seconds)
    enum RefreshIntervals {
        static let menuBar: TimeInterval = 30        // 30 seconds
        static let widgetSmall: TimeInterval = 900   // 15 minutes
        static let widgetMedium: TimeInterval = 900  // 15 minutes
        static let widgetLarge: TimeInterval = 1800  // 30 minutes
    }

    // Session window (5 hours in seconds)
    static let sessionWindow: TimeInterval = 5 * 60 * 60

    // Weekly limit (tokens)
    static let weeklyLimit = 1_000_000

    // Notification thresholds (percentages)
    enum NotificationThresholds {
        static let warning: Double = 75.0
        static let high: Double = 90.0
        static let critical: Double = 95.0
    }

    // GitHub repository
    static let githubRepoURL = "https://github.com/hamed-elfayome/Claude-Usage-Tracker"

    // GitHub star prompt timing (in seconds)
    enum GitHubPromptTiming {
        static let initialDelay: TimeInterval = 24 * 60 * 60  // 1 day
        static let reminderInterval: TimeInterval = 10 * 24 * 60 * 60  // 10 days (between 7-14 days)
    }
}
