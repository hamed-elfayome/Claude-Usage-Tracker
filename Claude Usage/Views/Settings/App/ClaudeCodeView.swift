//
//  ClaudeCodeView.swift
//  Claude Usage - Claude Code Statusline Integration
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Claude Code statusline integration settings
struct ClaudeCodeView: View {
    // Component visibility settings
    @State private var showDirectory: Bool = SharedDataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = SharedDataStore.shared.loadStatuslineShowBranch()
    @State private var showUsage: Bool = SharedDataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = SharedDataStore.shared.loadStatuslineShowProgressBar()
    @State private var showResetTime: Bool = SharedDataStore.shared.loadStatuslineShowResetTime()

    // Status feedback
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "claudecode.title".localized,
                    subtitle: "claudecode.subtitle".localized
                )

            // Preview Card (keep as is - user loves it!)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                HStack {
                    Label("claudecode.preview_label".localized, systemImage: "eye.fill")
                        .font(DesignTokens.Typography.sectionTitle)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("ui.updates_realtime".localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(generatePreview())
                        .font(DesignTokens.Typography.monospaced)
                        .foregroundColor(.accentColor)
                        .padding(DesignTokens.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .fill(Color.accentColor.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                )
                        )

                    Text("claudecode.preview_description".localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(DesignTokens.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(DesignTokens.Colors.cardBackground)
            )

            // Components - Simple and clean
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                Text("ui.display_components".localized)
                    .font(DesignTokens.Typography.sectionTitle)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Toggle("claudecode.component_directory".localized, isOn: $showDirectory)
                        .font(DesignTokens.Typography.body)

                    Toggle("claudecode.component_branch".localized, isOn: $showBranch)
                        .font(DesignTokens.Typography.body)

                    Toggle("claudecode.component_usage".localized, isOn: $showUsage)
                        .font(DesignTokens.Typography.body)

                    if showUsage {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 20)
                            Toggle("claudecode.component_progressbar".localized, isOn: $showProgressBar)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 0) {
                            Spacer().frame(width: 20)
                            Toggle("claudecode.component_resettime".localized, isOn: $showResetTime)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Action buttons - compact
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Button(action: applyConfiguration) {
                    Text("claudecode.button_apply".localized)
                        .font(DesignTokens.Typography.body)
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)

                Button(action: resetConfiguration) {
                    Text("claudecode.button_reset".localized)
                        .font(DesignTokens.Typography.body)
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
            }

            // Status message
            if let message = statusMessage {
                HStack(spacing: DesignTokens.Spacing.iconText) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isSuccess ? .green : .red)

                    Text(message)
                        .font(DesignTokens.Typography.body)

                    Spacer()

                    Button(action: { statusMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignTokens.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill((isSuccess ? Color.green : Color.red).opacity(0.1))
                )
            }

            // Info - minimal
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("ui.requirements".localized)
                    .font(DesignTokens.Typography.sectionTitle)

                Text("claudecode.requirement_sessionkey".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)

                Text("claudecode.requirement_restart".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            }
            .padding()
        }
    }

    // MARK: - Actions

    /// Applies the current configuration to Claude Code statusline.
    /// Installs scripts, updates config file, and enables statusline in settings.json.
    private func applyConfiguration() {
        // Validate: at least one component must be selected
        guard showDirectory || showBranch || showUsage else {
            statusMessage = "claudecode.error_no_components".localized
            isSuccess = false
            return
        }

        // Validate: session key must be configured
        guard StatuslineService.shared.hasValidSessionKey() else {
            statusMessage = "claudecode.error_no_sessionkey".localized
            isSuccess = false
            return
        }

        // Save user preferences
        SharedDataStore.shared.saveStatuslineShowDirectory(showDirectory)
        SharedDataStore.shared.saveStatuslineShowBranch(showBranch)
        SharedDataStore.shared.saveStatuslineShowUsage(showUsage)
        SharedDataStore.shared.saveStatuslineShowProgressBar(showProgressBar)
        SharedDataStore.shared.saveStatuslineShowResetTime(showResetTime)

        do {
            // Install scripts to ~/.claude/
            try StatuslineService.shared.installScripts()

            // Write configuration file
            try StatuslineService.shared.updateConfiguration(
                showDirectory: showDirectory,
                showBranch: showBranch,
                showUsage: showUsage,
                showProgressBar: showProgressBar,
                showResetTime: showResetTime
            )

            // Update Claude CLI settings.json
            try StatuslineService.shared.updateClaudeCodeSettings(enabled: true)

            statusMessage = "claudecode.success_applied".localized
            isSuccess = true
        } catch {
            statusMessage = "error.generic".localized(with: error.localizedDescription)
            isSuccess = false
        }
    }

    /// Disables the statusline by removing it from Claude CLI settings.json.
    private func resetConfiguration() {
        do {
            try StatuslineService.shared.updateClaudeCodeSettings(enabled: false)
            statusMessage = "claudecode.success_disabled".localized
            isSuccess = true
        } catch {
            statusMessage = "error.generic".localized(with: error.localizedDescription)
            isSuccess = false
        }
    }

    /// Generates a preview of what the statusline will look like based on current selections.
    private func generatePreview() -> String {
        var parts: [String] = []

        if showDirectory {
            parts.append("claude-usage")
        }

        if showBranch {
            parts.append("⎇ main")
        }

        if showUsage {
            var usageText = "Usage: 29%"
            if showProgressBar {
                usageText += " ▓▓▓░░░░░░░"
            }
            if showResetTime {
                usageText += " → Reset: 14:30"
            }
            parts.append(usageText)
        }

        return parts.isEmpty ? "claudecode.preview_no_components".localized : parts.joined(separator: " │ ")
    }
}

// MARK: - Previews

#Preview {
    ClaudeCodeView()
        .frame(width: 520, height: 600)
}
