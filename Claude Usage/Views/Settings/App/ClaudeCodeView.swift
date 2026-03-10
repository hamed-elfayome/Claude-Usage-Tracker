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
    @State private var showModel: Bool = SharedDataStore.shared.loadStatuslineShowModel()
    @State private var showDirectory: Bool = SharedDataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = SharedDataStore.shared.loadStatuslineShowBranch()
    @State private var showContext: Bool = SharedDataStore.shared.loadStatuslineShowContext()
    @State private var contextAsTokens: Bool = SharedDataStore.shared.loadStatuslineContextAsTokens()
    @State private var showUsage: Bool = SharedDataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = SharedDataStore.shared.loadStatuslineShowProgressBar()
    @State private var showResetTime: Bool = SharedDataStore.shared.loadStatuslineShowResetTime()
    @State private var showProfile: Bool = SharedDataStore.shared.loadStatuslineShowProfile()
    @State private var showPaceMarker: Bool = SharedDataStore.shared.loadStatuslineShowPaceMarker()
    @State private var paceMarkerStepColors: Bool = SharedDataStore.shared.loadStatuslinePaceMarkerStepColors()
    @State private var showContextLabel: Bool = SharedDataStore.shared.loadStatuslineShowContextLabel()

    // Status feedback
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = true

    // MARK: - Terminal-Matching Colors (ANSI standard)
    private enum TerminalColors {
        static let blue = Color(red: 0/255, green: 0/255, blue: 238/255)
        static let green = Color(red: 0/255, green: 187/255, blue: 0/255)
        static let yellow = Color(red: 187/255, green: 187/255, blue: 0/255)
        static let magenta = Color(red: 187/255, green: 0/255, blue: 187/255)
        static let cyan = Color(red: 0/255, green: 187/255, blue: 187/255)
        static let gray = Color(red: 128/255, green: 128/255, blue: 128/255)

        static let paceComfortable = Color(red: 0/255, green: 175/255, blue: 0/255)
        static let paceOnTrack = Color(red: 0/255, green: 175/255, blue: 175/255)
        static let paceWarming = Color(red: 215/255, green: 175/255, blue: 0/255)
        static let pacePressing = Color(red: 255/255, green: 135/255, blue: 0/255)
        static let paceCritical = Color(red: 215/255, green: 0/255, blue: 0/255)
        static let paceRunaway = Color(red: 175/255, green: 95/255, blue: 255/255)

        static func usageLevel(_ percentage: Int) -> Color {
            switch percentage {
            case 0...10:  return Color(red: 0/255, green: 95/255, blue: 0/255)
            case 11...20: return Color(red: 0/255, green: 135/255, blue: 0/255)
            case 21...30: return Color(red: 0/255, green: 175/255, blue: 0/255)
            case 31...40: return Color(red: 135/255, green: 135/255, blue: 0/255)
            case 41...50: return Color(red: 175/255, green: 175/255, blue: 0/255)
            case 51...60: return Color(red: 215/255, green: 175/255, blue: 0/255)
            case 61...70: return Color(red: 215/255, green: 135/255, blue: 0/255)
            case 71...80: return Color(red: 215/255, green: 95/255, blue: 0/255)
            case 81...90: return Color(red: 215/255, green: 0/255, blue: 0/255)
            default:      return Color(red: 175/255, green: 0/255, blue: 0/255)
            }
        }

        static func paceColor(for status: PaceStatus) -> Color {
            switch status {
            case .comfortable: return paceComfortable
            case .onTrack:     return paceOnTrack
            case .warming:     return paceWarming
            case .pressing:    return pacePressing
            case .critical:    return paceCritical
            case .runaway:     return paceRunaway
            }
        }
    }

    // MARK: - Multi-Color Preview

    private var multiColorPreview: some View {
        let percentage = 29
        let usageColor = TerminalColors.usageLevel(percentage)
        let ctxPrefix = showContextLabel ? "Ctx: " : ""

        return HStack(spacing: 0) {
            let parts: [(String, Color)] = {
                var p: [(String, Color)] = []

                if showDirectory {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    p.append(("claude-usage", TerminalColors.blue))
                }

                if showBranch {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    p.append(("⎇ main", TerminalColors.green))
                }

                if showModel {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    p.append(("Opus", TerminalColors.yellow))
                }

                if showProfile {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    let name = ProfileManager.shared.activeProfile?.name ?? "Profile"
                    p.append((name, TerminalColors.magenta))
                }

                if showContext {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    if contextAsTokens {
                        p.append(("\(ctxPrefix)96K", TerminalColors.cyan))
                    } else {
                        p.append(("\(ctxPrefix)48%", TerminalColors.cyan))
                    }
                }

                if showUsage {
                    if !p.isEmpty { p.append((" | ", TerminalColors.gray)) }
                    p.append(("Usage: \(percentage)%", usageColor))
                }

                return p
            }()

            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.0)
                    .foregroundColor(part.1)
            }

            if showUsage && showProgressBar {
                let filledBlocks = max(0, min(10, (percentage * 10 + 50) / 100))
                let emptyBlocks = 10 - filledBlocks

                if showPaceMarker {
                    let markerPos = max(0, min(9, previewMarkerPosition))
                    let paceColor = previewPaceColor(percentage: percentage)
                    let fullBar = String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                    let chars = Array(fullBar)
                    Text(" " + String(chars.prefix(markerPos)))
                        .foregroundColor(usageColor)
                    Text("┃")
                        .foregroundColor(paceColor)
                    Text(String(chars.suffix(from: markerPos + 1)))
                        .foregroundColor(usageColor)
                } else {
                    let bar = String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks)
                    Text(" \(bar)")
                        .foregroundColor(usageColor)
                }
            }

            if showUsage && showResetTime {
                Text(" → Reset: 14:30")
                    .foregroundColor(usageColor)
            }
        }
        .font(DesignTokens.Typography.monospaced)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "claudecode.title".localized,
                    subtitle: "claudecode.subtitle".localized
                )

                // Preview Card
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
                        multiColorPreview
                            .padding(DesignTokens.Spacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                    .fill(Color(.windowBackgroundColor).opacity(0.4))
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

                // Components + Actions (single card)
                SettingsSectionCard(
                    title: "ui.display_components".localized
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(
                            title: "claudecode.component_directory".localized,
                            isOn: $showDirectory
                        )

                        SettingToggle(
                            title: "claudecode.component_branch".localized,
                            isOn: $showBranch
                        )

                        SettingToggle(
                            title: "claudecode.component_model".localized,
                            isOn: $showModel
                        )

                        SettingToggle(
                            title: "claudecode.component_profile".localized,
                            isOn: $showProfile
                        )

                        // Context with sub-option
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            SettingToggle(
                                title: "claudecode.component_context".localized,
                                isOn: $showContext
                            )

                            if showContext {
                                SettingToggle(
                                    title: "claudecode.component_context_tokens".localized,
                                    description: "claudecode.context_info".localized,
                                    isOn: $contextAsTokens
                                )
                                .padding(.leading, DesignTokens.Spacing.cardPadding)
                            }
                        }

                        // Usage with sub-options
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            SettingToggle(
                                title: "claudecode.component_usage".localized,
                                isOn: $showUsage
                            )

                            if showUsage {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                    SettingToggle(
                                        title: "claudecode.component_progressbar".localized,
                                        isOn: $showProgressBar
                                    )

                                    if showProgressBar {
                                        SettingToggle(
                                            title: "Pace marker",
                                            description: "Show time-elapsed marker on progress bar",
                                            isOn: $showPaceMarker
                                        )
                                        .padding(.leading, DesignTokens.Spacing.cardPadding)

                                        if showPaceMarker {
                                            SettingToggle(
                                                title: "Pace tier colors",
                                                description: "Color by projected usage rate",
                                                isOn: $paceMarkerStepColors
                                            )
                                            .padding(.leading, DesignTokens.Spacing.cardPadding * 2)
                                        }
                                    }

                                    SettingToggle(
                                        title: "claudecode.component_resettime".localized,
                                        isOn: $showResetTime
                                    )
                                }
                                .padding(.leading, DesignTokens.Spacing.cardPadding)
                            }
                        }

                        Divider()

                        // Label toggles
                        if showContext {
                            SettingToggle(
                                title: "Show \"Ctx:\" label",
                                isOn: $showContextLabel
                            )
                        }

                        Divider()

                        HStack(spacing: DesignTokens.Spacing.small) {
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

                        if let message = statusMessage {
                            HStack(spacing: DesignTokens.Spacing.iconText) {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(isSuccess ? DesignTokens.Colors.success : DesignTokens.Colors.error)

                                Text(message)
                                    .font(DesignTokens.Typography.caption)

                                Spacer()

                                Button(action: { statusMessage = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(DesignTokens.Spacing.small)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.tiny)
                                    .fill((isSuccess ? Color.green : Color.red).opacity(0.08))
                            )
                        }

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            Text("claudecode.requirement_sessionkey".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)

                            Text("claudecode.requirement_restart".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Preview Helpers

    private var previewMarkerPosition: Int {
        if let usage = ProfileManager.shared.activeProfile?.claudeUsage {
            let remaining = usage.sessionResetTime.timeIntervalSince(Date())
            if remaining > 0 && remaining < 18000 {
                let elapsed = 18000 - remaining
                return max(0, min(9, Int(round(elapsed * 10.0 / 18000.0))))
            }
        }
        return 6
    }

    private func previewPaceColor(percentage: Int) -> Color {
        guard paceMarkerStepColors else {
            return TerminalColors.usageLevel(percentage)
        }
        let elapsedFraction: Double
        if let usage = ProfileManager.shared.activeProfile?.claudeUsage {
            let remaining = usage.sessionResetTime.timeIntervalSince(Date())
            if remaining > 0 && remaining < 18000 {
                elapsedFraction = (18000 - remaining) / 18000
            } else {
                elapsedFraction = 0.6
            }
        } else {
            elapsedFraction = 0.6
        }
        if let paceStatus = PaceStatus.calculate(usedPercentage: Double(percentage), elapsedFraction: elapsedFraction) {
            return TerminalColors.paceColor(for: paceStatus)
        }
        return TerminalColors.usageLevel(percentage)
    }

    // MARK: - Actions

    /// Applies the current configuration to Claude Code statusline.
    /// Installs scripts, updates config file, and enables statusline in settings.json.
    private func applyConfiguration() {
        // Validate: at least one component must be selected
        guard showModel || showDirectory || showBranch || showContext || showUsage || showProfile else {
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
        SharedDataStore.shared.saveStatuslineShowModel(showModel)
        SharedDataStore.shared.saveStatuslineShowDirectory(showDirectory)
        SharedDataStore.shared.saveStatuslineShowBranch(showBranch)
        SharedDataStore.shared.saveStatuslineShowContext(showContext)
        SharedDataStore.shared.saveStatuslineContextAsTokens(contextAsTokens)
        SharedDataStore.shared.saveStatuslineShowUsage(showUsage)
        SharedDataStore.shared.saveStatuslineShowProgressBar(showProgressBar)
        SharedDataStore.shared.saveStatuslineShowResetTime(showResetTime)
        SharedDataStore.shared.saveStatuslineShowProfile(showProfile)
        SharedDataStore.shared.saveStatuslineShowPaceMarker(showPaceMarker)
        SharedDataStore.shared.saveStatuslinePaceMarkerStepColors(paceMarkerStepColors)
        SharedDataStore.shared.saveStatuslineShowContextLabel(showContextLabel)

        do {
            // Install scripts to ~/.claude/
            try StatuslineService.shared.installScripts()

            // Write configuration file
            let profileName = ProfileManager.shared.activeProfile?.name ?? ""
            try StatuslineService.shared.updateConfiguration(
                showModel: showModel,
                showDirectory: showDirectory,
                showBranch: showBranch,
                showContext: showContext,
                contextAsTokens: contextAsTokens,
                showUsage: showUsage,
                showProgressBar: showProgressBar,
                showResetTime: showResetTime,
                showProfile: showProfile,
                profileName: profileName,
                showPaceMarker: showPaceMarker,
                paceMarkerStepColors: paceMarkerStepColors,
                showContextLabel: showContextLabel
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
        let ctxPrefix = showContextLabel ? "Ctx: " : ""

        if showDirectory {
            parts.append("claude-usage")
        }

        if showBranch {
            parts.append("⎇ main")
        }

        if showModel {
            parts.append("Opus")
        }

        if showProfile {
            let name = ProfileManager.shared.activeProfile?.name ?? "Profile"
            parts.append(name)
        }

        if showContext {
            if contextAsTokens {
                parts.append("\(ctxPrefix)96K")
            } else {
                parts.append("\(ctxPrefix)48%")
            }
        }

        if showUsage {
            let percentage = 29
            let filledBlocks = max(0, min(10, (percentage * 10 + 50) / 100))
            let emptyBlocks = 10 - filledBlocks
            var usageText = "Usage: \(percentage)%"
            if showProgressBar {
                var barChars = Array(String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks))
                if showPaceMarker {
                    let markerPos = max(0, min(9, previewMarkerPosition))
                    barChars[markerPos] = "┃"
                }
                usageText += " \(String(barChars))"
            }
            if showResetTime {
                usageText += " → Reset: 14:30"
            }
            parts.append(usageText)
        }

        return parts.isEmpty ? "claudecode.preview_no_components".localized : parts.joined(separator: " | ")
    }
}

// MARK: - Previews

#Preview {
    ClaudeCodeView()
        .frame(width: 520, height: 600)
}
