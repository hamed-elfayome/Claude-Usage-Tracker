//
//  GeneralSettingsView.swift
//  Claude Usage - General Profile Settings
//
//  Flat section layout with dividers (Behavior) + card (Notifications)
//

import SwiftUI
import UserNotifications

/// General profile settings: Launch at Login, Refresh interval, Auto-start, Notifications
struct GeneralSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "general.title".localized,
                    subtitle: "general.subtitle".localized
                )

                // MARK: - Behavior Section (flat)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("general.behavior_section".localized)
                        .font(DesignTokens.Typography.sectionTitle)

                    // Launch at Login (app-wide, not profile-specific)
                    SettingToggle(
                        title: "general.launch_at_login".localized,
                        description: "general.launch_at_login.description".localized,
                        isOn: $launchAtLogin
                    )
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.shared.setEnabled(newValue)
                    }

                    if let profile = profileManager.activeProfile {
                        Divider()

                        // Auto-Start Session
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

                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                Text("ui.requirements".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                Text("general.autostart_requirement".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Auto-Rotate Profiles
                        if profileManager.profiles.count > 1 {
                            Divider()

                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                SettingToggle(
                                    title: "general.autorotate_toggle".localized,
                                    description: "general.autorotate_description".localized,
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
                                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                        Text("general.autorotate_threshold".localized)
                                            .font(DesignTokens.Typography.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)

                                        Picker("", selection: Binding(
                                            get: { profile.autoRotateThreshold },
                                            set: { newValue in
                                                var updated = profile
                                                updated.autoRotateThreshold = newValue
                                                profileManager.updateProfile(updated)
                                            }
                                        )) {
                                            Text("50%").tag(50)
                                            Text("60%").tag(60)
                                            Text("70%").tag(70)
                                            Text("75%").tag(75)
                                            Text("80%").tag(80)
                                            Text("85%").tag(85)
                                            Text("90%").tag(90)
                                            Text("95%").tag(95)
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: 120)
                                    }
                                }
                            }
                        }

                        Divider()

                        // Refresh Interval
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
                }

                // MARK: - Notifications Section (keep card — complex group)
                if let profile = profileManager.activeProfile {
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

                                // Sound picker
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                    Text("notifications.sound".localized)
                                        .font(DesignTokens.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    Picker("", selection: Binding(
                                        get: { profile.notificationSettings.soundName },
                                        set: { newValue in
                                            var updated = profile
                                            updated.notificationSettings.soundName = newValue
                                            profileManager.updateProfile(updated)
                                        }
                                    )) {
                                        Text("notifications.sound.default".localized).tag("default")
                                        Text("notifications.sound.none".localized).tag("none")
                                        Divider()
                                        Text("Basso").tag("Basso")
                                        Text("Blow").tag("Blow")
                                        Text("Bottle").tag("Bottle")
                                        Text("Frog").tag("Frog")
                                        Text("Funk").tag("Funk")
                                        Text("Glass").tag("Glass")
                                        Text("Hero").tag("Hero")
                                        Text("Morse").tag("Morse")
                                        Text("Ping").tag("Ping")
                                        Text("Pop").tag("Pop")
                                        Text("Purr").tag("Purr")
                                        Text("Sosumi").tag("Sosumi")
                                        Text("Submarine").tag("Submarine")
                                        Text("Tink").tag("Tink")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 200)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                    HStack {
                                        Text("notifications.alert_thresholds".localized)
                                            .font(DesignTokens.Typography.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)

                                        Spacer()

                                        Menu {
                                            ForEach([50, 60, 70, 75, 80, 85, 90, 95], id: \.self) { value in
                                                if !profile.notificationSettings.customThresholds.contains(value) {
                                                    Button("\(value)%") {
                                                        var updated = profile
                                                        updated.notificationSettings.customThresholds.append(value)
                                                        updated.notificationSettings.customThresholds.sort()
                                                        profileManager.updateProfile(updated)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: DesignTokens.Icons.small))
                                                .foregroundColor(DesignTokens.Colors.accent)
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 20)
                                    }

                                    VStack(spacing: DesignTokens.Spacing.small) {
                                        ForEach(profile.notificationSettings.customThresholds.sorted(), id: \.self) { threshold in
                                            HStack {
                                                ThresholdIndicator(
                                                    level: "\(threshold)%",
                                                    color: colorForThreshold(threshold),
                                                    label: labelForThreshold(threshold)
                                                )

                                                Button(action: {
                                                    var updated = profile
                                                    updated.notificationSettings.customThresholds.removeAll { $0 == threshold }
                                                    profileManager.updateProfile(updated)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: DesignTokens.Icons.small))
                                                        .foregroundColor(.secondary.opacity(0.5))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }

                                        // Session reset is always shown (not removable)
                                        ThresholdIndicator(level: "0%", color: DesignTokens.Colors.success, label: "notifications.threshold.session_reset".localized)
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

    private func colorForThreshold(_ threshold: Int) -> Color {
        if threshold >= 95 { return DesignTokens.Colors.error }
        if threshold >= 90 { return DesignTokens.Colors.warning }
        if threshold >= 75 { return Color.yellow }
        return DesignTokens.Colors.success
    }

    private func labelForThreshold(_ threshold: Int) -> String {
        if threshold >= 95 { return "notifications.threshold.critical".localized }
        if threshold >= 90 { return "notifications.threshold.high".localized }
        if threshold >= 75 { return "notifications.threshold.warning".localized }
        return "notifications.threshold.info".localized
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

// MARK: - Previews

#Preview {
    GeneralSettingsView()
        .frame(width: 520, height: 600)
}
