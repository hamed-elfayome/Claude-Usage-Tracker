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

                                // Built-in thresholds (toggleable)
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                    Text("notifications.alert_thresholds".localized)
                                        .font(DesignTokens.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    VStack(spacing: DesignTokens.Spacing.small) {
                                        ThresholdToggleRow(
                                            level: "75%",
                                            color: SettingsColors.usageMedium,
                                            label: "notifications.threshold.warning".localized,
                                            isOn: Binding(
                                                get: { profile.notificationSettings.threshold75Enabled },
                                                set: { newValue in
                                                    var updated = profile
                                                    updated.notificationSettings.threshold75Enabled = newValue
                                                    profileManager.updateProfile(updated)
                                                }
                                            )
                                        )
                                        ThresholdToggleRow(
                                            level: "90%",
                                            color: SettingsColors.usageHigh,
                                            label: "notifications.threshold.high".localized,
                                            isOn: Binding(
                                                get: { profile.notificationSettings.threshold90Enabled },
                                                set: { newValue in
                                                    var updated = profile
                                                    updated.notificationSettings.threshold90Enabled = newValue
                                                    profileManager.updateProfile(updated)
                                                }
                                            )
                                        )
                                        ThresholdToggleRow(
                                            level: "95%",
                                            color: SettingsColors.usageCritical,
                                            label: "notifications.threshold.critical".localized,
                                            isOn: Binding(
                                                get: { profile.notificationSettings.threshold95Enabled },
                                                set: { newValue in
                                                    var updated = profile
                                                    updated.notificationSettings.threshold95Enabled = newValue
                                                    profileManager.updateProfile(updated)
                                                }
                                            )
                                        )
                                        ThresholdIndicator(level: "0%", color: SettingsColors.usageLow, label: "notifications.threshold.session_reset".localized)
                                    }
                                }

                                // Custom thresholds
                                Divider()

                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                    Text("notifications.custom_thresholds".localized)
                                        .font(DesignTokens.Typography.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    CustomThresholdsEditor(
                                        thresholds: Binding(
                                            get: { profile.notificationSettings.customThresholds },
                                            set: { newValue in
                                                var updated = profile
                                                updated.notificationSettings.customThresholds = newValue
                                                profileManager.updateProfile(updated)
                                            }
                                        )
                                    )
                                }

                                // Sound picker
                                Divider()

                                NotificationSoundPicker(
                                    soundName: Binding(
                                        get: { profile.notificationSettings.soundName },
                                        set: { newValue in
                                            var updated = profile
                                            updated.notificationSettings.soundName = newValue
                                            profileManager.updateProfile(updated)
                                        }
                                    )
                                )
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

// MARK: - Threshold Toggle Row

struct ThresholdToggleRow: View {
    let level: String
    let color: Color
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(level)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 32, alignment: .leading)

            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

// MARK: - Custom Thresholds Editor

struct CustomThresholdsEditor: View {
    @Binding var thresholds: [Int]
    @State private var newThresholdText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            // Existing custom thresholds
            if !thresholds.isEmpty {
                ForEach(thresholds.sorted(), id: \.self) { threshold in
                    HStack(spacing: DesignTokens.Spacing.small) {
                        Circle()
                            .fill(colorForThreshold(threshold))
                            .frame(width: 8, height: 8)

                        Text("\(threshold)%")
                            .font(DesignTokens.Typography.caption)
                            .fontWeight(.medium)

                        Text("notifications.custom_threshold".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            thresholds.removeAll { $0 == threshold }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add new threshold
            HStack(spacing: DesignTokens.Spacing.small) {
                TextField("notifications.custom_placeholder".localized, text: $newThresholdText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit { addThreshold() }

                Text("%")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)

                Button("notifications.custom_add".localized) {
                    addThreshold()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newThresholdText.isEmpty)
            }
        }
    }

    private func addThreshold() {
        guard let value = Int(newThresholdText),
              value > 0, value <= 100,
              !thresholds.contains(value),
              value != 75, value != 90, value != 95 else {
            newThresholdText = ""
            return
        }
        thresholds.append(value)
        newThresholdText = ""
    }

    private func colorForThreshold(_ threshold: Int) -> Color {
        switch threshold {
        case 90...: return SettingsColors.usageCritical
        case 70..<90: return SettingsColors.usageHigh
        case 50..<70: return SettingsColors.usageMedium
        default: return SettingsColors.usageLow
        }
    }
}

// MARK: - Notification Sound Picker

struct NotificationSoundPicker: View {
    @Binding var soundName: String

    private static let systemSounds: [(name: String, label: String)] = {
        let soundsDir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: soundsDir) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { file in
                let name = (file as NSString).deletingPathExtension
                return (name: name, label: name)
            }
            .sorted { $0.label < $1.label }
    }()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.iconText) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: DesignTokens.Icons.standard))
                .foregroundColor(DesignTokens.Colors.accent)
                .frame(width: DesignTokens.Spacing.iconFrame)

            Text("notifications.sound".localized)
                .font(DesignTokens.Typography.body)

            Spacer()

            Picker("", selection: $soundName) {
                Text("notifications.sound.default".localized).tag("default")
                Divider()
                ForEach(Self.systemSounds, id: \.name) { sound in
                    Text(sound.label).tag(sound.name)
                }
                Divider()
                Text("notifications.sound.none".localized).tag("none")
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            // Preview button
            Button(action: { previewSound() }) {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("notifications.sound.preview".localized)
        }
    }

    private func previewSound() {
        switch soundName {
        case "none":
            break
        case "default":
            NSSound.beep()
        default:
            if let sound = NSSound(named: NSSound.Name(soundName)) {
                sound.play()
            }
        }
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 520, height: 600)
}
