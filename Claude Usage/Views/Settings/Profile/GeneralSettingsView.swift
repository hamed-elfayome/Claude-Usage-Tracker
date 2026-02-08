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
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
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

                            // Requirement
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                Text("Requirements:")
                                    .font(DesignTokens.Typography.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                Text("general.autostart_requirement".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Auto-Rotate Profiles
                    if profileManager.profiles.filter({ $0.hasSessionCredentials }).count >= 2 {
                        SettingsSectionCard(
                            title: "general.autorotate_title".localized,
                            subtitle: "general.autorotate_subtitle".localized
                        ) {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                SettingToggle(
                                    title: "general.autorotate_toggle".localized,
                                    description: "general.autorotate_description".localized,
                                    badge: .new,
                                    isOn: Binding(
                                        get: { profile.autoRotateEnabled },
                                        set: { newValue in
                                            var updated = profile
                                            updated.autoRotateEnabled = newValue
                                            profileManager.updateProfile(updated)
                                        }
                                    )
                                )

                                if profile.autoRotateEnabled {
                                    Divider()

                                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                        Text("general.autorotate_profiles".localized)
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundColor(.secondary)

                                        ForEach(profileManager.profiles.filter({ $0.id != profile.id && $0.hasSessionCredentials })) { other in
                                            HStack(spacing: DesignTokens.Spacing.small) {
                                                Image(systemName: other.autoRotateEnabled ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(other.autoRotateEnabled ? .green : .secondary)

                                                Text(other.name)
                                                    .font(DesignTokens.Typography.body)

                                                if let tier = other.accountTier {
                                                    Text(tier.rawValue.uppercased())
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(Color.accentColor.opacity(0.7)))
                                                }

                                                Spacer()

                                                Toggle("", isOn: Binding(
                                                    get: { other.autoRotateEnabled },
                                                    set: { newValue in
                                                        var updated = other
                                                        updated.autoRotateEnabled = newValue
                                                        profileManager.updateProfile(updated)
                                                    }
                                                ))
                                                .labelsHidden()
                                                .toggleStyle(.switch)
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
