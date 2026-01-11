//
//  GeneralSettingsView.swift
//  Claude Usage - General Profile Settings
//
//  Refactored to use DesignTokens and SettingsSection components
//

import SwiftUI
import UserNotifications

/// General profile settings: Refresh interval, Auto-start, Notifications
struct GeneralSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "general.title".localized,
                    subtitle: "general.subtitle".localized
                )

                if let profile = profileManager.activeProfile {
                    // Refresh Interval
                    SettingsSectionCard(
                        title: "general.refresh_title".localized,
                        subtitle: "general.refresh_subtitle".localized
                    ) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Image(systemName: "clock")
                                    .font(.system(size: DesignTokens.Icons.standard))
                                    .foregroundColor(DesignTokens.Colors.accent)
                                    .frame(width: DesignTokens.Spacing.iconFrame)

                                Text(String(format: "general.refresh_seconds".localized, Int(profile.refreshInterval)))
                                    .font(DesignTokens.Typography.bodyMedium)

                                Spacer()
                            }

                            Slider(
                                value: Binding(
                                    get: { profile.refreshInterval },
                                    set: { newValue in
                                        var updated = profile
                                        updated.refreshInterval = newValue
                                        profileManager.updateProfile(updated)
                                    }
                                ),
                                in: 10...300,
                                step: 10
                            )

                            HStack {
                                Text("general.refresh_min".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("general.refresh_max".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Auto-Start Session
                    SettingsSectionCard(
                        title: "general.autostart_title".localized,
                        subtitle: "general.autostart_subtitle".localized
                    ) {
                        SettingToggle(
                            title: "general.autostart_toggle".localized,
                            description: "general.autostart_description".localized,
                            isOn: Binding(
                                get: { profile.autoStartSessionEnabled },
                                set: { newValue in
                                    var updated = profile
                                    updated.autoStartSessionEnabled = newValue
                                    profileManager.updateProfile(updated)
                                }
                            )
                        )
                    }

                    // Notifications
                    SettingsSectionCard(
                        title: "general.notifications_title".localized,
                        subtitle: "general.notifications_subtitle".localized
                    ) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                            SettingToggle(
                                title: "notifications.enable".localized,
                                description: "notifications.enable.description".localized,
                                isOn: Binding(
                                    get: { profile.notificationSettings.enabled },
                                    set: { newValue in
                                        var updated = profile
                                        updated.notificationSettings.enabled = newValue
                                        profileManager.updateProfile(updated)

                                        if newValue {
                                            requestNotificationPermission()
                                        }
                                    }
                                )
                            )

                            if profile.notificationSettings.enabled {
                                Divider()

                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                    Text("notifications.alert_thresholds".localized)
                                        .font(DesignTokens.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    VStack(spacing: DesignTokens.Spacing.small) {
                                        ThresholdIndicator(level: "75%", color: SettingsColors.usageMedium, label: "notifications.threshold.warning".localized)
                                        ThresholdIndicator(level: "90%", color: SettingsColors.usageHigh, label: "notifications.threshold.high".localized)
                                        ThresholdIndicator(level: "95%", color: SettingsColors.usageCritical, label: "notifications.threshold.critical".localized)
                                        ThresholdIndicator(level: "0%", color: SettingsColors.usageLow, label: "notifications.threshold.session_reset".localized)
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Helper Methods

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

// MARK: - Previews

#Preview {
    GeneralSettingsView()
        .frame(width: 520, height: 600)
}
