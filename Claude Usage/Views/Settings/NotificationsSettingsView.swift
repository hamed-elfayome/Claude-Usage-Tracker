//
//  NotificationsSettingsView.swift
//  Claude Usage - Notifications Settings
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI
import UserNotifications

/// Usage notifications and alerts settings
struct NotificationsSettingsView: View {
    @Binding var notificationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Enable Notifications Toggle
            SettingToggle(
                title: "Enable notifications",
                description: "Receive alerts when approaching usage limits",
                isOn: $notificationsEnabled
            )
            .onChange(of: notificationsEnabled) { _, newValue in
                DataStore.shared.saveNotificationsEnabled(newValue)

                if newValue {
                    requestNotificationPermission()
                }
            }

            if notificationsEnabled {
                Divider()
                    .padding(.vertical, 4)

                // Threshold indicators
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alert Thresholds")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(spacing: 6) {
                        ThresholdIndicator(level: "75%", color: SettingsColors.usageMedium, label: "Warning")
                        ThresholdIndicator(level: "90%", color: SettingsColors.usageHigh, label: "High Usage")
                        ThresholdIndicator(level: "95%", color: SettingsColors.usageCritical, label: "Critical")
                        ThresholdIndicator(level: "0%", color: SettingsColors.usageLow, label: "Session Reset")
                    }
                }
            }

            Spacer()
        }
        .padding(28)
    }

    private func requestNotificationPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .authorized {
                NotificationManager.shared.sendSimpleAlert(type: .notificationsEnabled)
            } else if settings.authorizationStatus == .notDetermined {
                let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted == true {
                    NotificationManager.shared.sendSimpleAlert(type: .notificationsEnabled)
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct ThresholdIndicator: View {
    let level: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: Spacing.iconTextSpacing) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(level)
                .font(Typography.monospacedInput)
                .foregroundColor(.primary)

            Text(label)
                .font(Typography.label)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

// MARK: - Previews

#Preview {
    NotificationsSettingsView(notificationsEnabled: .constant(true))
        .frame(width: 520, height: 600)
}
