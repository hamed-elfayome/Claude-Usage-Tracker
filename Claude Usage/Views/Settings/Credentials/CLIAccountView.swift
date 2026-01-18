//
//  CLIAccountView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import SwiftUI

struct CLIAccountView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var cliAccountInfo: CLIAccountInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "cli.title".localized,
                    subtitle: "cli.subtitle".localized
                )

                if let profile = profileManager.activeProfile {
                    // Professional Status Card
                    HStack(spacing: DesignTokens.Spacing.medium) {
                        Circle()
                            .fill(profile.hasCliAccount ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            Text(profile.hasCliAccount ? "cli.synced".localized : "cli.not_synced".localized)
                                .font(DesignTokens.Typography.bodyMedium)

                            if profile.hasCliAccount, let syncedAt = profile.cliAccountSyncedAt {
                                Text(syncedAt, style: .relative)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(DesignTokens.Spacing.medium)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                            .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
                    )

                    // Credentials & Actions Card
                    SettingsSectionCard(
                        title: "cli.account_details".localized,
                        subtitle: profile.hasCliAccount ? "cli.credentials_synced".localized : "cli.no_credentials".localized
                    ) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                            if profile.hasCliAccount, let json = profile.cliCredentialsJSON {
                                // Credentials Display
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                                    // Access Token
                                    if let sessionKey = extractSessionKey(from: json) {
                                        HStack(spacing: DesignTokens.Spacing.iconText) {
                                            Image(systemName: "key")
                                                .font(.system(size: DesignTokens.Icons.standard))
                                                .foregroundColor(.accentColor)
                                                .frame(width: DesignTokens.Spacing.iconFrame)

                                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                                                Text("cli.access_token".localized)
                                                    .font(DesignTokens.Typography.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.secondary)
                                                Text(maskCredential(sessionKey))
                                                    .font(DesignTokens.Typography.monospaced)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }

                                    // Account Info
                                    if let info = cliAccountInfo {
                                        Divider()

                                        HStack(spacing: DesignTokens.Spacing.iconText) {
                                            Image(systemName: "person.badge.key")
                                                .font(.system(size: DesignTokens.Icons.standard))
                                                .foregroundColor(.accentColor)
                                                .frame(width: DesignTokens.Spacing.iconFrame)

                                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                                                Text("cli.subscription".localized)
                                                    .font(DesignTokens.Typography.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.secondary)
                                                Text(info.subscriptionType)
                                                    .font(DesignTokens.Typography.body)
                                                    .foregroundColor(.primary)
                                            }
                                        }

                                        if !info.scopes.isEmpty {
                                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                                Image(systemName: "checkmark.shield")
                                                    .font(.system(size: DesignTokens.Icons.standard))
                                                    .foregroundColor(.accentColor)
                                                    .frame(width: DesignTokens.Spacing.iconFrame)

                                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                                                    Text("cli.scopes".localized)
                                                        .font(DesignTokens.Typography.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.secondary)
                                                    Text(info.scopes.joined(separator: ", "))
                                                        .font(DesignTokens.Typography.body)
                                                        .foregroundColor(.primary)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                // Not synced message
                                HStack(spacing: DesignTokens.Spacing.small) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: DesignTokens.Icons.standard))
                                        .foregroundColor(.orange)
                                    Text("cli.sync_instructions".localized)
                                        .font(DesignTokens.Typography.body)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            // Error message
                            if let error = syncError {
                                HStack(spacing: DesignTokens.Spacing.small) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: DesignTokens.Icons.standard))
                                    Text(error)
                                        .font(DesignTokens.Typography.body)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(DesignTokens.Spacing.iconText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(DesignTokens.Radius.small)
                            }

                            // Action Buttons
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Button(action: syncFromCLI) {
                                    HStack(spacing: DesignTokens.Spacing.extraSmall) {
                                        if isSyncing {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .frame(width: DesignTokens.Icons.small, height: DesignTokens.Icons.small)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: DesignTokens.Icons.small))
                                        }
                                        Text(profile.hasCliAccount ? "cli.resync".localized : "cli.sync_from_code".localized)
                                            .font(DesignTokens.Typography.body)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(isSyncing)

                                if profile.hasCliAccount {
                                    Button(action: removeSync) {
                                        HStack(spacing: DesignTokens.Spacing.extraSmall) {
                                            Image(systemName: "trash")
                                                .font(.system(size: DesignTokens.Icons.small))
                                            Text("common.remove".localized)
                                                .font(DesignTokens.Typography.body)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                    .foregroundColor(.red)
                                }

                                Spacer()
                            }
                        }
                    }

                    // Info Card
                    SettingsContentCard {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                            HStack(spacing: DesignTokens.Spacing.small) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: DesignTokens.Icons.standard))
                                Text("cli.about_title".localized)
                                    .font(DesignTokens.Typography.sectionTitle)
                            }

                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                                Text("cli.benefits".localized)
                                    .font(DesignTokens.Typography.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                                    BulletPoint("cli.benefit_1".localized)
                                    BulletPoint("cli.benefit_2".localized)
                                    BulletPoint("cli.benefit_3".localized)
                                }
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                            }

                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadCLIAccountInfo()
        }
        .onChange(of: profileManager.activeProfile?.id) { _, _ in
            // Reload when profile changes
            loadCLIAccountInfo()
            syncError = nil
        }
    }

    private func syncFromCLI() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        isSyncing = true
        syncError = nil

        do {
            try ClaudeCodeSyncService.shared.syncToProfile(profileId)

            // Reload profiles to get the updated cliCredentialsJSON
            profileManager.loadProfiles()

            // Update profile metadata
            if var updated = profileManager.activeProfile {
                updated.hasCliAccount = true
                updated.cliAccountSyncedAt = Date()
                profileManager.updateProfile(updated)
            }

            // Load account info
            loadCLIAccountInfo()

            LoggingService.shared.log("CLIAccountView: CLI sync complete, credentials saved to profile")
        } catch {
            syncError = error.localizedDescription
            LoggingService.shared.logError("CLIAccountView: CLI sync failed - \(error.localizedDescription)")
        }

        isSyncing = false
    }

    private func removeSync() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        do {
            try ClaudeCodeSyncService.shared.removeFromProfile(profileId)

            // Reload profiles to get the updated profile without cliCredentialsJSON
            profileManager.loadProfiles()

            // Update profile metadata
            if var updated = profileManager.activeProfile {
                updated.hasCliAccount = false
                updated.cliAccountSyncedAt = nil
                profileManager.updateProfile(updated)
            }

            cliAccountInfo = nil
            LoggingService.shared.log("CLIAccountView: CLI credentials removed from profile")
        } catch {
            syncError = error.localizedDescription
            LoggingService.shared.logError("CLIAccountView: Failed to remove CLI credentials - \(error.localizedDescription)")
        }
    }

    private func loadCLIAccountInfo() {
        guard let profile = profileManager.activeProfile else {
            LoggingService.shared.logError("CLIAccountView: No active profile")
            cliAccountInfo = nil
            return
        }

        guard let json = profile.cliCredentialsJSON else {
            LoggingService.shared.log("CLIAccountView: No CLI credentials JSON in profile")
            cliAccountInfo = nil
            return
        }

        LoggingService.shared.log("CLIAccountView: Loading CLI account info from JSON")
        cliAccountInfo = parseCLIInfo(from: json)

        if cliAccountInfo != nil {
            LoggingService.shared.log("CLIAccountView: CLI account info parsed successfully")
        } else {
            LoggingService.shared.logError("CLIAccountView: Failed to parse CLI account info")
        }
    }

    private func parseCLIInfo(from json: String) -> CLIAccountInfo? {
        let info = ClaudeCodeSyncService.shared.extractSubscriptionInfo(from: json)
        guard let info = info else { return nil }
        return CLIAccountInfo(subscriptionType: info.type, scopes: info.scopes)
    }

    /// Extracts the access token from CLI credentials JSON (OAuth)
    private func extractSessionKey(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = parsed["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String else {
            return nil
        }
        return accessToken
    }

    /// Masks a credential for display (shows first 12 and last 4 characters)
    private func maskCredential(_ credential: String) -> String {
        guard credential.count > 20 else { return "•••••••••" }
        let prefix = String(credential.prefix(12))
        let suffix = String(credential.suffix(4))
        return "\(prefix)•••••\(suffix)"
    }
}

struct CLIAccountInfo {
    let subscriptionType: String
    let scopes: [String]
}
