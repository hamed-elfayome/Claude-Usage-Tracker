//
//  UpdatesSettingsView.swift
//  Claude Usage
//
//  Software update settings and controls
//

import SwiftUI

struct UpdatesSettingsView: View {
    @StateObject private var updateManager = UpdateManager.shared
    @State private var autoUpdateEnabled: Bool = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var lastCheckDescription: String {
        guard let lastCheck = updateManager.lastUpdateCheckDate else {
            return "settings.updates.never_checked".localized
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastCheck, relativeTo: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
                // Header
                SettingsHeader(
                    title: "settings.updates.title".localized,
                    subtitle: "settings.updates.description".localized
                )

                Divider()

                // Version Info Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Version Information")
                        .font(Typography.sectionHeader)

                    VStack(spacing: Spacing.sm) {
                        // Current Version
                        HStack {
                            HStack(spacing: Spacing.iconTextSpacing) {
                                Image(systemName: "app.badge")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 20)
                                Text("settings.updates.current_version".localized)
                                    .font(Typography.body)
                            }
                            Spacer()
                            Text("v\(appVersion) (\(buildNumber))")
                                .font(Typography.monospacedValue)
                                .foregroundColor(.secondary)
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                        // Last Check
                        HStack {
                            HStack(spacing: Spacing.iconTextSpacing) {
                                Image(systemName: "clock")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 20)
                                Text("settings.updates.last_check".localized)
                                    .font(Typography.body)
                            }
                            Spacer()
                            Text(lastCheckDescription)
                                .font(Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }

                Divider()

                // Automatic Updates Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Update Preferences")
                        .font(Typography.sectionHeader)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack {
                            HStack(spacing: Spacing.iconTextSpacing) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 20)
                                Text("settings.updates.automatic".localized)
                                    .font(Typography.body)
                            }
                            Spacer()
                            Toggle("", isOn: $autoUpdateEnabled)
                                .labelsHidden()
                                .onChange(of: autoUpdateEnabled) { _, newValue in
                                    updateManager.setAutomaticChecksEnabled(newValue)
                                }
                        }

                        Text("settings.updates.automatic.description".localized)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                // Check Now Button
                SettingsButton.primary(
                    title: "settings.updates.check_now".localized,
                    icon: "arrow.down.circle",
                    action: {
                        updateManager.checkForUpdates()
                    }
                )
                .disabled(!updateManager.canCheckForUpdates)

                // Info Box
                HStack(spacing: Spacing.md) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.updates.info.title".localized)
                            .font(Typography.body)
                        Text("settings.updates.info.description".localized)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                        .fill(Color.blue.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )

                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            autoUpdateEnabled = updateManager.automaticChecksEnabled
        }
    }
}

#Preview {
    UpdatesSettingsView()
        .frame(width: 520, height: 600)
}
