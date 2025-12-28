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
    @State private var showDirectory: Bool = DataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = DataStore.shared.loadStatuslineShowBranch()
    @State private var showUsage: Bool = DataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = DataStore.shared.loadStatuslineShowProgressBar()

    // Status feedback
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "claudecode.title".localized,
                subtitle: "claudecode.subtitle".localized
            )

            Divider()

            // Preview Card (keep as is - user loves it!)
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("claudecode.preview_label".localized, systemImage: "eye.fill")
                        .font(Typography.sectionHeader)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("ui.updates_realtime".localized)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(generatePreview())
                        .font(Typography.monospacedInput)
                        .foregroundColor(.accentColor)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                .fill(Color.accentColor.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                )
                        )

                    Text("claudecode.preview_description".localized)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusLarge)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Components - Simple and clean
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("ui.display_components".localized)
                    .font(Typography.sectionHeader)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle("claudecode.component_directory".localized, isOn: $showDirectory)
                        .font(Typography.label)

                    Toggle("claudecode.component_branch".localized, isOn: $showBranch)
                        .font(Typography.label)

                    Toggle("claudecode.component_usage".localized, isOn: $showUsage)
                        .font(Typography.label)

                    if showUsage {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 20)
                            Toggle("claudecode.component_progressbar".localized, isOn: $showProgressBar)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Action buttons - compact
            HStack(spacing: Spacing.buttonRowSpacing) {
                Button(action: applyConfiguration) {
                    Text("claudecode.button_apply".localized)
                        .font(Typography.label)
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)

                Button(action: resetConfiguration) {
                    Text("claudecode.button_reset".localized)
                        .font(Typography.label)
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
            }

            // Status message
            if let message = statusMessage {
                HStack(spacing: Spacing.iconTextSpacing) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isSuccess ? .green : .red)

                    Text(message)
                        .font(Typography.label)

                    Spacer()

                    Button(action: { statusMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.inputPadding)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                        .fill((isSuccess ? Color.green : Color.red).opacity(0.1))
                )
            }

            // Info - minimal
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("ui.requirements".localized)
                    .font(Typography.sectionHeader)

                Text("claudecode.requirement_sessionkey".localized)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)

                Text("claudecode.requirement_restart".localized)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .contentPadding()
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
        DataStore.shared.saveStatuslineShowDirectory(showDirectory)
        DataStore.shared.saveStatuslineShowBranch(showBranch)
        DataStore.shared.saveStatuslineShowUsage(showUsage)
        DataStore.shared.saveStatuslineShowProgressBar(showProgressBar)

        do {
            // Install scripts to ~/.claude/
            try StatuslineService.shared.installScripts()

            // Write configuration file
            try StatuslineService.shared.updateConfiguration(
                showDirectory: showDirectory,
                showBranch: showBranch,
                showUsage: showUsage,
                showProgressBar: showProgressBar
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
            parts.append(showProgressBar ? "Usage: 29% ▓▓▓░░░░░░░" : "Usage: 29%")
        }

        return parts.isEmpty ? "claudecode.preview_no_components".localized : parts.joined(separator: " │ ")
    }
}

// MARK: - Previews

#Preview {
    ClaudeCodeView()
        .frame(width: 520, height: 600)
}
