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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "settings.updates.title".localized,
                    subtitle: "settings.updates.description".localized
                )

                // Version Info Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("updates.version_info".localized)
                        .font(DesignTokens.Typography.sectionTitle)

                    VStack(spacing: DesignTokens.Spacing.small) {
                        // Current Version
                        HStack {
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Image(systemName: "app.badge")
                                    .font(.system(size: DesignTokens.Icons.standard))
                                    .foregroundColor(.accentColor)
                                    .frame(width: DesignTokens.Spacing.iconFrame)
                                Text("settings.updates.current_version".localized)
                                    .font(DesignTokens.Typography.body)
                            }
                            Spacer()
                            Text("v\(appVersion) (\(buildNumber))")
                                .font(DesignTokens.Typography.monospaced)
                                .foregroundColor(.secondary)
                        }
                        .padding(DesignTokens.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .fill(DesignTokens.Colors.cardBackground)
                        )

                        // Last Check
                        HStack {
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Image(systemName: "clock")
                                    .font(.system(size: DesignTokens.Icons.standard))
                                    .foregroundColor(.accentColor)
                                    .frame(width: DesignTokens.Spacing.iconFrame)
                                Text("settings.updates.last_check".localized)
                                    .font(DesignTokens.Typography.body)
                            }
                            Spacer()
                            Text(lastCheckDescription)
                                .font(DesignTokens.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(DesignTokens.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .fill(DesignTokens.Colors.cardBackground)
                        )
                    }
                }

                Divider()

                // Automatic Updates Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("updates.update_preferences".localized)
                        .font(DesignTokens.Typography.sectionTitle)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        HStack {
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: DesignTokens.Icons.standard))
                                    .foregroundColor(.accentColor)
                                    .frame(width: DesignTokens.Spacing.iconFrame)
                                Text("settings.updates.automatic".localized)
                                    .font(DesignTokens.Typography.body)
                            }
                            Spacer()
                            Toggle("", isOn: $autoUpdateEnabled)
                                .labelsHidden()
                                .onChange(of: autoUpdateEnabled) { _, newValue in
                                    updateManager.setAutomaticChecksEnabled(newValue)
                                }
                        }

                        Text("settings.updates.automatic.description".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
                    }
                    .padding(DesignTokens.Spacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                            .fill(DesignTokens.Colors.cardBackground)
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
                HStack(spacing: DesignTokens.Spacing.medium) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DesignTokens.Icons.standard))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.updates.info.title".localized)
                            .font(DesignTokens.Typography.body)
                        Text("settings.updates.info.description".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(Color.blue.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
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
