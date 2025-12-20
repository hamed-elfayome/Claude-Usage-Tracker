//
//  NotificationServiceProtocol.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

/// Protocol defining notification operations
/// Enables dependency injection and testing with mock notification services
protocol NotificationServiceProtocol {
    /// Checks usage and sends notifications if thresholds are crossed
    func checkAndNotify(usage: ClaudeUsage)

    /// Clears all pending notifications
    func clearAllNotifications()
}
