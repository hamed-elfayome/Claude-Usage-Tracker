//
//  CodexAccountView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  Credentials view for OpenAI Codex profiles: auto-detects the Codex CLI's
//  ~/.codex/auth.json (read live by default), with a manual paste fallback
//  and a connection test against the usage endpoint.
//

import SwiftUI

struct CodexAccountView: View {
    @StateObject private var profileManager = ProfileManager.shared

    @State private var detectedCredentials: CodexCredentials?
    @State private var manualJSON: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var saveError: String?

    private enum TestResult {
        case success(plan: String?)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "codex.title".localized,
                    subtitle: "codex.subtitle".localized
                )

                if let profile = profileManager.activeProfile {
                    statusCard(for: profile)
                    detectionCard(for: profile)
                    manualEntryCard(for: profile)
                }
            }
            .padding()
        }
        .onAppear { refreshDetection() }
    }

    // MARK: - Status

    private func statusCard(for profile: Profile) -> some View {
        let usesManual = profile.codexCredentialsJSON != nil
        let connected = usesManual || detectedCredentials != nil

        return HStack(spacing: DesignTokens.Spacing.medium) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                Text(connected ? "codex.connected".localized : "codex.not_connected".localized)
                    .font(DesignTokens.Typography.bodyMedium)

                if connected {
                    if usesManual {
                        Text("codex.source_manual".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    } else if let email = detectedCredentials?.email {
                        Text("codex.signed_in_as".localized(with: email))
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("codex.source_authfile".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                testConnection(for: profile)
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("codex.test_connection".localized)
                }
            }
            .disabled(isTesting || !connected)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Auto-detection

    private func detectionCard(for profile: Profile) -> some View {
        SettingsSectionCard(
            title: "codex.cli_detection_title".localized,
            subtitle: "codex.cli_detection_subtitle".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if let credentials = detectedCredentials {
                    HStack(spacing: DesignTokens.Spacing.iconText) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DesignTokens.Icons.standard))
                            .foregroundColor(.green)
                            .frame(width: DesignTokens.Spacing.iconFrame)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            Text("codex.cli_detected".localized)
                                .font(DesignTokens.Typography.body)
                            if let email = credentials.email {
                                Text(email)
                                    .font(DesignTokens.Typography.monospaced)
                                    .foregroundColor(.secondary)
                            }
                            if let lastRefresh = credentials.lastRefresh {
                                Text("codex.last_refresh".localized(with: relativeString(lastRefresh)))
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if profile.codexCredentialsJSON == nil {
                        Text("codex.live_read_note".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: DesignTokens.Spacing.iconText) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: DesignTokens.Icons.standard))
                            .foregroundColor(.orange)
                            .frame(width: DesignTokens.Spacing.iconFrame)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            Text("codex.cli_not_detected".localized)
                                .font(DesignTokens.Typography.body)
                            Text("codex.cli_not_detected_hint".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Button("codex.rescan".localized) {
                        refreshDetection()
                    }

                    if let result = testResult {
                        switch result {
                        case .success(let plan):
                            Label(
                                plan.map { "codex.test_success_plan".localized(with: $0.capitalized) }
                                    ?? "codex.test_success".localized,
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Manual entry

    private func manualEntryCard(for profile: Profile) -> some View {
        SettingsSectionCard(
            title: "codex.manual_title".localized,
            subtitle: "codex.manual_subtitle".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if profile.codexCredentialsJSON != nil {
                    HStack(spacing: DesignTokens.Spacing.iconText) {
                        Image(systemName: "key.fill")
                            .font(.system(size: DesignTokens.Icons.standard))
                            .foregroundColor(.accentColor)
                            .frame(width: DesignTokens.Spacing.iconFrame)
                        Text("codex.manual_saved".localized)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Button("codex.manual_remove".localized, role: .destructive) {
                            saveManualCredentials(nil, for: profile)
                        }
                    }
                } else {
                    TextEditor(text: $manualJSON)
                        .font(DesignTokens.Typography.monospaced)
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
                        )

                    HStack {
                        Button("codex.manual_save".localized) {
                            saveManualCredentials(manualJSON, for: profile)
                        }
                        .disabled(manualJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let saveError {
                            Text(saveError)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refreshDetection() {
        detectedCredentials = try? CodexAuthService.shared.loadFromAuthFile()
    }

    private func saveManualCredentials(_ json: String?, for profile: Profile) {
        saveError = nil
        if let json {
            guard CodexAuthService.parse(Data(json.utf8)) != nil else {
                saveError = "error.codex_credentials_invalid".localized
                return
            }
        }
        var updated = profile
        updated.codexCredentialsJSON = json
        profileManager.updateProfile(updated)
        if json == nil { manualJSON = "" }
    }

    private func testConnection(for profile: Profile) {
        isTesting = true
        testResult = nil
        Task {
            do {
                let usage = try await CodexUsageProvider.shared.fetchUsage(for: profile)
                await MainActor.run {
                    testResult = .success(plan: usage.planType)
                    isTesting = false
                }
            } catch {
                let message = (error as? AppError)?.message ?? error.localizedDescription
                await MainActor.run {
                    testResult = .failure(message)
                    isTesting = false
                }
            }
        }
    }

    private func relativeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
