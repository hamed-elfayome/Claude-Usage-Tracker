//
//  ClaudeCodeView.swift
//  Claude Usage - Claude Code Statusline Integration
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Claude Code statusline integration settings
struct ClaudeCodeView: View {
    @ObservedObject private var profileManager = ProfileManager.shared

    // Component visibility settings
    @State private var showDirectory: Bool = SharedDataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = SharedDataStore.shared.loadStatuslineShowBranch()
    @State private var showUsage: Bool = SharedDataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = SharedDataStore.shared.loadStatuslineShowProgressBar()
    @State private var showResetTime: Bool = SharedDataStore.shared.loadStatuslineShowResetTime()
    @State private var use24HourTime: Bool = SharedDataStore.shared.loadStatuslineUse24HourTime()
    @State private var showUsageLabel: Bool = SharedDataStore.shared.loadStatuslineShowUsageLabel()
    @State private var showResetLabel: Bool = SharedDataStore.shared.loadStatuslineShowResetLabel()

    // Appearance settings
    @State private var colorMode: StatuslineColorMode = SharedDataStore.shared.loadStatuslineColorMode()
    @State private var singleColor: Color = Color(hex: SharedDataStore.shared.loadStatuslineSingleColorHex()) ?? .cyan

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
                    previewView
                        .padding(DesignTokens.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .fill(previewBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .strokeBorder(previewBorderColor, lineWidth: 1)
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

            // Two-column layout: Components | Colors
            HStack(alignment: .top, spacing: 16) {
                // Left: Display Components
                SettingsSectionCard(
                    title: "ui.display_components".localized,
                    subtitle: "Choose which elements to display"
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Toggle("claudecode.component_directory".localized, isOn: $showDirectory)
                            .font(DesignTokens.Typography.body)

                        Toggle("claudecode.component_branch".localized, isOn: $showBranch)
                            .font(DesignTokens.Typography.body)

                        Toggle("claudecode.component_usage".localized, isOn: $showUsage)
                            .font(DesignTokens.Typography.body)

                        if showUsage {
                            // Components
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

                            if showResetTime {
                                HStack(spacing: 0) {
                                    Spacer().frame(width: 40)
                                    Toggle("24-hour time format", isOn: $use24HourTime)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Divider
                            Divider()
                                .padding(.leading, 20)
                                .padding(.vertical, 4)

                            HStack(spacing: 0) {
                                Spacer().frame(width: 20)
                                Toggle("Show \"Usage:\" label", isOn: $showUsageLabel)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }

                            if showResetTime {
                                HStack(spacing: 0) {
                                    Spacer().frame(width: 20)
                                    Toggle("Show \"Reset:\" label", isOn: $showResetLabel)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Right: Color Mode Settings
                SettingsSectionCard(
                    title: "Statusline Colors",
                    subtitle: "Choose color display mode"
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        ForEach([StatuslineColorMode.colored, .monochrome, .singleColor], id: \.self) { mode in
                            Button {
                                colorMode = mode
                                SharedDataStore.shared.saveStatuslineColorMode(mode)
                            } label: {
                                HStack {
                                    Image(systemName: colorMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(colorMode == mode ? .accentColor : .secondary)

                                    Image(systemName: mode.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(iconColorForMode(mode))
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(DesignTokens.Typography.body)
                                            .foregroundColor(.primary)

                                        Text(mode.description)
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }

                        if colorMode == .singleColor {
                            HStack {
                                Spacer().frame(width: 20)

                                ColorPicker("Choose Color", selection: Binding(
                                    get: { singleColor },
                                    set: { newColor in
                                        singleColor = newColor
                                        SharedDataStore.shared.saveStatuslineSingleColorHex(newColor.toHex() ?? "#00BFFF")
                                    }
                                ))
                                .labelsHidden()

                                Text("Custom statusline color")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
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

    // MARK: - Computed Properties

    /// Color used for preview based on selected color mode (from Menu Bar Settings)
    private var previewColor: Color {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()
        switch colorMode {
        case .colored:
            return .accentColor
        case .monochrome:
            return .primary
        case .singleColor:
            let hex = SharedDataStore.shared.loadStatuslineSingleColorHex()
            return Color(hex: hex) ?? .cyan
        }
    }

    /// Background color for preview card
    private var previewBackgroundColor: Color {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()
        switch colorMode {
        case .colored:
            return Color.purple.opacity(0.05)
        case .monochrome:
            return previewColor.opacity(0.05)
        case .singleColor:
            return previewColor.opacity(0.05)
        }
    }

    /// Border color for preview card
    private var previewBorderColor: Color {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()
        switch colorMode {
        case .colored:
            return Color.purple.opacity(0.2)
        case .monochrome:
            return previewColor.opacity(0.2)
        case .singleColor:
            return previewColor.opacity(0.2)
        }
    }

    /// Preview view showing statusline with appropriate colors
    @ViewBuilder
    private var previewView: some View {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()

        if colorMode == .colored {
            // Multi-color preview - each element gets its own color
            multiColorPreview
        } else {
            // Single color preview (monochrome or single color)
            Text(generatePreview())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(previewColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Multi-color preview showing each element in different colors
    private var multiColorPreview: some View {
        let usage = profileManager.activeProfile?.claudeUsage
        let percentage = usage != nil ? Int(usage!.sessionPercentage) : 29
        let usageColor = colorForPercentage(Double(percentage))

        return HStack(spacing: 0) {
            if showDirectory {
                Text("claude-usage")
                    .foregroundColor(.cyan)
                if showBranch || showUsage {
                    Text(" │ ").foregroundColor(.secondary)
                }
            }

            if showBranch {
                Text("⎇ main")
                    .foregroundColor(.green)
                if showUsage {
                    Text(" │ ").foregroundColor(.secondary)
                }
            }

            if showUsage {
                let usagePrefix = showUsageLabel ? "Usage: " : ""
                Text(usagePrefix + "\(percentage)%")
                    .foregroundColor(usageColor)

                if showProgressBar {
                    let filledBlocks = max(0, min(10, (percentage + 5) / 10))
                    let emptyBlocks = 10 - filledBlocks
                    let bar = String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                    Text(" \(bar)")
                        .foregroundColor(usageColor)
                }

                if showResetTime {
                    let resetTimeString = formatResetTime(usage?.sessionResetTime)
                    let resetPrefix = showResetLabel ? " → Reset: " : " → "
                    Text(resetPrefix + resetTimeString)
                        .foregroundColor(usageColor)
                }
            }

            if !showDirectory && !showBranch && !showUsage {
                Text("claudecode.preview_no_components".localized)
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Returns the appropriate color for usage percentage based on thresholds
    private func colorForPercentage(_ percentage: Double) -> Color {
        switch percentage {
        case 0..<50:
            return SettingsColors.usageLow       // Green
        case 50..<80:
            return SettingsColors.usageHigh      // Orange
        default: // 80%+
            return SettingsColors.usageCritical  // Red
        }
    }

    /// Formats reset time for preview display
    /// Rounds to nearest minute to prevent display flickering
    private func formatResetTime(_ date: Date?) -> String {
        guard let date = date else {
            return "--:--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date.roundedToNearestMinute())
    }

    /// Returns the appropriate icon color for each color mode
    private func iconColorForMode(_ mode: StatuslineColorMode) -> Color {
        switch mode {
        case .colored:
            return .purple
        case .monochrome:
            return .primary
        case .singleColor:
            return singleColor
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

        // Load color settings from SharedDataStore (configured in Menu Bar Settings)
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()
        let singleColorHex = SharedDataStore.shared.loadStatuslineSingleColorHex()

        // Save user preferences
        SharedDataStore.shared.saveStatuslineShowDirectory(showDirectory)
        SharedDataStore.shared.saveStatuslineShowBranch(showBranch)
        SharedDataStore.shared.saveStatuslineShowUsage(showUsage)
        SharedDataStore.shared.saveStatuslineShowProgressBar(showProgressBar)
        SharedDataStore.shared.saveStatuslineShowResetTime(showResetTime)
        SharedDataStore.shared.saveStatuslineUse24HourTime(use24HourTime)
        SharedDataStore.shared.saveStatuslineShowUsageLabel(showUsageLabel)
        SharedDataStore.shared.saveStatuslineShowResetLabel(showResetLabel)

        do {
            // Install scripts to ~/.claude/
            try StatuslineService.shared.installScripts()

            // Write configuration file
            try StatuslineService.shared.updateConfiguration(
                showDirectory: showDirectory,
                showBranch: showBranch,
                showUsage: showUsage,
                showProgressBar: showProgressBar,
                showResetTime: showResetTime,
                use24HourTime: use24HourTime,
                showUsageLabel: showUsageLabel,
                showResetLabel: showResetLabel,
                colorMode: colorMode,
                singleColorHex: singleColorHex
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
            // Use real usage data if available
            let usage = profileManager.activeProfile?.claudeUsage
            let percentage = usage != nil ? Int(usage!.sessionPercentage) : 29

            var usageText = showUsageLabel ? "Usage: \(percentage)%" : "\(percentage)%"

            if showProgressBar {
                let filledBlocks = max(0, min(10, (percentage + 5) / 10))
                let emptyBlocks = 10 - filledBlocks
                let bar = String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                usageText += " \(bar)"
            }

            if showResetTime {
                if let resetTime = usage?.sessionResetTime {
                    let formatter = DateFormatter()
                    formatter.dateFormat = use24HourTime ? "HH:mm" : "h:mm a"
                    let resetPrefix = showResetLabel ? " → Reset: " : " → "
                    usageText += "\(resetPrefix)\(formatter.string(from: resetTime.roundedToNearestMinute()))"
                } else {
                    let resetPrefix = showResetLabel ? " → Reset: " : " → "
                    usageText += "\(resetPrefix)--:--"
                }
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
