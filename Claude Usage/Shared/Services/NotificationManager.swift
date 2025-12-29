import Foundation
import UserNotifications

/// Manages user notifications for usage threshold alerts
class NotificationManager: NotificationServiceProtocol {
    static let shared = NotificationManager()

    // Track previous session percentage to detect resets
    private var previousSessionPercentage: Double = 0.0

    // Track which notifications have been sent to prevent duplicates
    private var sentNotifications: Set<String> = []

    private init() {}

    /// Sends a notification when approaching usage limits
    func sendUsageAlert(type: AlertType, percentage: Double, resetTime: Date?) {
        // Check if notifications are enabled in preferences
        guard DataStore.shared.loadNotificationsEnabled() else {
            return
        }

        // Create unique identifier for this notification
        let identifier = "\(type.rawValue)_\(Int(percentage))"

        // Check if we've already sent this notification
        guard !sentNotifications.contains(identifier) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.message(percentage: percentage, resetTime: resetTime)
        content.sound = .default
        content.categoryIdentifier = "USAGE_ALERT"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error == nil {
                // Mark this notification as sent
                self?.sentNotifications.insert(identifier)
            }
        }
    }

    /// Sends a simple notification (for non-usage alerts)
    func sendSimpleAlert(type: AlertType) {
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.message(percentage: 0, resetTime: nil)
        content.sound = .default
        content.categoryIdentifier = "INFO_ALERT"

        let request = UNNotificationRequest(
            identifier: type.rawValue,
            content: content,
            trigger: nil // Show immediately
        )

        UNUserNotificationCenter.current().add(request) { _ in
            // Notification sent
        }
    }

    /// Sends a brief success notification for user-triggered refreshes
    func sendSuccessNotification() {
        let center = UNUserNotificationCenter.current()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Updated"
        content.body = "Successfully loaded usage data"
        // Silent notification (no sound)
        content.categoryIdentifier = "SUCCESS_ALERT"

        // Create a trigger to deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create the request with a unique identifier
        let identifier = "usage_refresh_success_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Add the notification request
        center.add(request) { error in
            if let error = error {
                LoggingService.shared.logError("Failed to show success notification: \(error)")
            }
        }

        // Auto-remove after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    /// Checks usage and sends appropriate alerts
    func checkAndNotify(usage: ClaudeUsage) {
        // Session usage alerts
        let sessionPercentage = usage.sessionPercentage

        // Check for session reset (went from >0% to 0%)
        if previousSessionPercentage > 0.0 && sessionPercentage == 0.0 {
            sendUsageAlert(
                type: .sessionReset,
                percentage: sessionPercentage,
                resetTime: usage.sessionResetTime
            )

            // Auto-start new session if enabled
            if DataStore.shared.loadAutoStartSessionEnabled() {
                Task {
                    do {
                        try await ClaudeAPIService().sendInitializationMessage()
                        // Send notification on successful auto-start
                        await MainActor.run {
                            self.sendSimpleAlert(type: .sessionAutoStarted)
                        }
                    } catch {
                        // Silently fail - don't interrupt the user
                    }
                }
            }
        }

        // Update previous percentage for next check
        previousSessionPercentage = sessionPercentage

        // Clear lower threshold notifications to allow re-notification
        clearLowerThresholdNotifications(currentPercentage: sessionPercentage)

        if sessionPercentage >= Constants.NotificationThresholds.critical {
            sendUsageAlert(
                type: .sessionCritical,
                percentage: sessionPercentage,
                resetTime: usage.sessionResetTime
            )
        } else if sessionPercentage >= Constants.NotificationThresholds.warning {
            sendUsageAlert(
                type: .sessionWarning,
                percentage: sessionPercentage,
                resetTime: usage.sessionResetTime
            )
        }

        // Weekly usage alerts
        let weeklyPercentage = usage.weeklyPercentage
        clearLowerThresholdNotifications(currentPercentage: weeklyPercentage)

        if weeklyPercentage >= Constants.NotificationThresholds.critical {
            sendUsageAlert(
                type: .weeklyCritical,
                percentage: weeklyPercentage,
                resetTime: usage.weeklyResetTime
            )
        } else if weeklyPercentage >= Constants.NotificationThresholds.warning {
            sendUsageAlert(
                type: .weeklyWarning,
                percentage: weeklyPercentage,
                resetTime: usage.weeklyResetTime
            )
        }

        // Opus usage alerts (if applicable)
        if usage.opusWeeklyTokensUsed > 0 {
            let opusPercentage = usage.opusWeeklyPercentage
            clearLowerThresholdNotifications(currentPercentage: opusPercentage)

            if opusPercentage >= Constants.NotificationThresholds.critical {
                sendUsageAlert(
                    type: .opusCritical,
                    percentage: opusPercentage,
                    resetTime: usage.weeklyResetTime
                )
            } else if opusPercentage >= Constants.NotificationThresholds.warning {
                sendUsageAlert(
                    type: .opusWarning,
                    percentage: opusPercentage,
                    resetTime: usage.weeklyResetTime
                )
            }
        }
    }

    /// Clears all pending notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Clears sent notification tracking for lower percentages
    /// This allows re-notification if usage goes back up
    private func clearLowerThresholdNotifications(currentPercentage: Double) {
        // Remove notifications for percentages lower than current
        sentNotifications = sentNotifications.filter { identifier in
            // Extract percentage from identifier (format: "type_percentage")
            let components = identifier.components(separatedBy: "_")
            guard components.count >= 2,
                  let percentage = Double(components.last ?? "0") else {
                return true // Keep if we can't parse
            }
            return percentage >= currentPercentage
        }
    }
}

// MARK: - Alert Types

extension NotificationManager {
    enum AlertType: String {
        case sessionWarning = "session_warning"
        case sessionCritical = "session_critical"
        case sessionReset = "session_reset"
        case sessionAutoStarted = "session_auto_started"
        case weeklyWarning = "weekly_warning"
        case weeklyCritical = "weekly_critical"
        case opusWarning = "opus_warning"
        case opusCritical = "opus_critical"
        case notificationsEnabled = "notifications_enabled"

        var title: String {
            switch self {
            case .sessionWarning:
                return "notification.session_warning.title".localized
            case .sessionCritical:
                return "notification.session_critical.title".localized
            case .sessionReset:
                return "notification.session_reset.title".localized
            case .sessionAutoStarted:
                return "notification.session_auto_started.title".localized
            case .weeklyWarning:
                return "notification.weekly_warning.title".localized
            case .weeklyCritical:
                return "notification.weekly_critical.title".localized
            case .opusWarning:
                return "notification.opus_warning.title".localized
            case .opusCritical:
                return "notification.opus_critical.title".localized
            case .notificationsEnabled:
                return "notification.enabled.title".localized
            }
        }

        func message(percentage: Double, resetTime: Date?) -> String {
            let percentStr = String(format: "%.1f%%", percentage)
            let resetStr = resetTime.map { "Resets \(FormatterHelper.timeUntilReset(from: $0))" } ?? ""

            switch self {
            case .sessionWarning:
                return "notification.session_warning.message".localized(with: percentStr, resetStr)
            case .sessionCritical:
                return "notification.session_critical.message".localized(with: percentStr, resetStr)
            case .sessionReset:
                return "notification.session_reset.message".localized
            case .sessionAutoStarted:
                return "notification.session_auto_started.message".localized
            case .weeklyWarning:
                return "notification.weekly_warning.message".localized(with: percentStr, resetStr)
            case .weeklyCritical:
                return "notification.weekly_critical.message".localized(with: percentStr, resetStr)
            case .opusWarning:
                return "notification.opus_warning.message".localized(with: percentStr, resetStr)
            case .opusCritical:
                return "notification.opus_critical.message".localized(with: percentStr, resetStr)
            case .notificationsEnabled:
                return "notification.enabled.message".localized
            }
        }
    }
}
