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
    @State private var showModel: Bool = SharedDataStore.shared.loadStatuslineShowModel()
    @State private var showDirectory: Bool = SharedDataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = SharedDataStore.shared.loadStatuslineShowBranch()
    @State private var showContext: Bool = SharedDataStore.shared.loadStatuslineShowContext()
    @State private var contextAsTokens: Bool = SharedDataStore.shared.loadStatuslineContextAsTokens()
    @State private var showUsage: Bool = SharedDataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = SharedDataStore.shared.loadStatuslineShowProgressBar()
    @State private var showPaceMarker: Bool = SharedDataStore.shared.loadStatuslineShowPaceMarker()
    @State private var paceMarkerStepColors: Bool = SharedDataStore.shared.loadStatuslinePaceMarkerStepColors()
    @State private var showResetTime: Bool = SharedDataStore.shared.loadStatuslineShowResetTime()
    @State private var showProfile: Bool = SharedDataStore.shared.loadStatuslineShowProfile()
    @State private var use24HourTime: Bool = SharedDataStore.shared.loadStatuslineUse24HourTime()
    @State private var showUsageLabel: Bool = SharedDataStore.shared.loadStatuslineShowUsageLabel()
    @State private var showContextLabel: Bool = SharedDataStore.shared.loadStatuslineShowContextLabel()
    @State private var showResetLabel: Bool = SharedDataStore.shared.loadStatuslineShowResetLabel()
    @State private var showWeekly: Bool = SharedDataStore.shared.loadStatuslineShowWeekly()
    @State private var showWeeklyBar: Bool = SharedDataStore.shared.loadStatuslineShowWeeklyBar()
    @State private var showWeeklyPaceMarker: Bool = SharedDataStore.shared.loadStatuslineShowWeeklyPaceMarker()
    @State private var showWeeklyResetTime: Bool = SharedDataStore.shared.loadStatuslineShowWeeklyResetTime()
    @State private var showWeeklyLabel: Bool = SharedDataStore.shared.loadStatuslineShowWeeklyLabel()
    @State private var showExtraUsage: Bool = SharedDataStore.shared.loadStatuslineShowExtraUsage()

    // Appearance settings
    @State private var colorMode: StatuslineColorMode = SharedDataStore.shared.loadStatuslineColorMode()
    @State private var singleColor: Color = Color(hex: SharedDataStore.shared.loadStatuslineSingleColorHex()) ?? .cyan
    @State private var elementColors: StatuslineElementColors = SharedDataStore.shared.loadStatuslineElementColors()
    @State private var elementColorsExpanded: Bool = false

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

                // Color Mode Card
                SettingsSectionCard(
                    title: "Statusline Colors",
                    subtitle: "Choose color display mode"
                ) {
                    HStack(spacing: DesignTokens.Spacing.small) {
                        ForEach([StatuslineColorMode.colored, .monochrome, .singleColor, .perElement], id: \.self) { mode in
                            Button {
                                colorMode = mode
                                SharedDataStore.shared.saveStatuslineColorMode(mode)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 12))
                                        .foregroundColor(iconColorForMode(mode))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mode.displayName)
                                            .font(DesignTokens.Typography.body)
                                            .foregroundColor(.primary)

                                        Text(mode.description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .fill(colorMode == mode ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .strokeBorder(colorMode == mode ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if colorMode == .singleColor {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            ColorPicker("Custom color", selection: Binding(
                                get: { singleColor },
                                set: { newColor in
                                    singleColor = newColor
                                    SharedDataStore.shared.saveStatuslineSingleColorHex(newColor.toHex() ?? "#00BFFF")
                                }
                            ))
                            .font(DesignTokens.Typography.caption)

                            Spacer()
                        }
                        .padding(.top, 4)
                    }

                    if colorMode == .perElement {
                        DisclosureGroup(isExpanded: $elementColorsExpanded) {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                ElementColorRow(label: "claudecode.element_color_directory".localized, hex: $elementColors.directoryHex)
                                ElementColorRow(label: "claudecode.element_color_branch".localized, hex: $elementColors.branchHex)
                                ElementColorRow(label: "claudecode.element_color_model".localized, hex: $elementColors.modelHex)
                                ElementColorRow(label: "claudecode.element_color_profile".localized, hex: $elementColors.profileHex)
                                ElementColorRow(label: "claudecode.element_color_context".localized, hex: $elementColors.contextHex)
                                ElementColorRow(label: "claudecode.element_color_separator".localized, hex: $elementColors.separatorHex)

                                Divider()

                                ElementColorRowOptional(
                                    label: "claudecode.element_color_usage".localized,
                                    description: "claudecode.element_color_usage_desc".localized,
                                    hex: $elementColors.usageBaseHex
                                )
                                ElementColorRowOptional(
                                    label: "claudecode.element_color_pace".localized,
                                    description: "claudecode.element_color_pace_desc".localized,
                                    hex: $elementColors.paceBaseHex
                                )
                                ElementColorRowOptional(
                                    label: "claudecode.element_color_weekly".localized,
                                    description: "claudecode.element_color_weekly_desc".localized,
                                    hex: $elementColors.weeklyBaseHex
                                )
                                ElementColorRowOptional(
                                    label: "claudecode.element_color_extra".localized,
                                    description: "claudecode.element_color_extra_desc".localized,
                                    hex: $elementColors.extraUsageBaseHex
                                )
                            }
                            .padding(.top, DesignTokens.Spacing.small)
                        } label: {
                            Text("claudecode.element_colors_title".localized)
                                .font(DesignTokens.Typography.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 4)
                        .onChange(of: elementColors) {
                            SharedDataStore.shared.saveStatuslineElementColors(elementColors)
                        }
                    }
                }

                // Display Components
                SettingsSectionCard(
                    title: "ui.display_components".localized,
                    subtitle: "Choose which elements to display"
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
                                            title: "claudecode.component_pace_marker".localized,
                                            description: "claudecode.pace_marker_info".localized,
                                            isOn: $showPaceMarker
                                        )
                                        .padding(.leading, DesignTokens.Spacing.cardPadding)

                                        if showPaceMarker {
                                            SettingToggle(
                                                title: "Pace tier colors",
                                                description: "6-tier projected pace (green → purple)",
                                                isOn: $paceMarkerStepColors
                                            )
                                            .padding(.leading, DesignTokens.Spacing.cardPadding * 2)
                                        }
                                    }

                                    SettingToggle(
                                        title: "claudecode.component_resettime".localized,
                                        isOn: $showResetTime
                                    )

                                    if showResetTime {
                                        SettingToggle(
                                            title: "24-hour time format",
                                            isOn: $use24HourTime
                                        )
                                        .padding(.leading, DesignTokens.Spacing.cardPadding)
                                    }

                                    Divider()

                                    if showContext {
                                        SettingToggle(
                                            title: "Show \"Ctx:\" label",
                                            isOn: $showContextLabel
                                        )
                                    }

                                    SettingToggle(
                                        title: "Show \"Usage:\" label",
                                        isOn: $showUsageLabel
                                    )

                                    if showResetTime {
                                        SettingToggle(
                                            title: "Show \"Reset:\" label",
                                            isOn: $showResetLabel
                                        )
                                    }

                                    Divider()

                                    // Weekly with sub-options
                                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                        SettingToggle(
                                            title: "claudecode.component_weekly".localized,
                                            description: "claudecode.component_weekly_description".localized,
                                            isOn: $showWeekly
                                        )

                                        if showWeekly {
                                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                                SettingToggle(
                                                    title: "claudecode.component_progressbar".localized,
                                                    isOn: $showWeeklyBar
                                                )

                                                if showWeeklyBar {
                                                    SettingToggle(
                                                        title: "claudecode.component_pace_marker".localized,
                                                        description: "claudecode.pace_marker_info".localized,
                                                        isOn: $showWeeklyPaceMarker
                                                    )
                                                    .padding(.leading, DesignTokens.Spacing.cardPadding)
                                                }

                                                SettingToggle(
                                                    title: "claudecode.component_resettime".localized,
                                                    isOn: $showWeeklyResetTime
                                                )

                                                SettingToggle(
                                                    title: "claudecode.weekly_label".localized,
                                                    isOn: $showWeeklyLabel
                                                )
                                            }
                                            .padding(.leading, DesignTokens.Spacing.cardPadding)
                                        }
                                    }

                                    SettingToggle(
                                        title: "claudecode.component_extra_usage".localized,
                                        description: "claudecode.component_extra_usage_description".localized,
                                        isOn: $showExtraUsage
                                    )
                                }
                                .padding(.leading, DesignTokens.Spacing.cardPadding)
                            }
                        }
                    }

                    Divider()

                    // Action buttons + status
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
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
        case .perElement:
            return Color(hex: elementColors.directoryHex) ?? TerminalColors.blue
        }
    }

    /// Background color for preview card
    private var previewBackgroundColor: Color {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()
        switch colorMode {
        case .colored, .perElement:
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
        case .colored, .perElement:
            return Color.purple.opacity(0.2)
        case .monochrome:
            return previewColor.opacity(0.2)
        case .singleColor:
            return previewColor.opacity(0.2)
        }
    }

    // Per-element preview colors — read from elementColors state for live updates
    private var previewDirectoryColor: Color { Color(hex: elementColors.directoryHex) ?? TerminalColors.blue }
    private var previewBranchColor: Color    { Color(hex: elementColors.branchHex) ?? TerminalColors.green }
    private var previewModelColor: Color     { Color(hex: elementColors.modelHex) ?? TerminalColors.yellow }
    private var previewProfileColor: Color   { Color(hex: elementColors.profileHex) ?? TerminalColors.magenta }
    private var previewContextColor: Color   { Color(hex: elementColors.contextHex) ?? TerminalColors.cyan }
    private var previewSeparatorColor: Color { Color(hex: elementColors.separatorHex) ?? TerminalColors.gray }
    private func previewUsageColor(percentage: Int) -> Color {
        if let hex = elementColors.usageBaseHex { return Color(hex: hex) ?? TerminalColors.usageLevel(percentage) }
        return TerminalColors.usageLevel(percentage)
    }
    private func previewPaceOverrideColor(percentage: Int) -> Color? {
        if let hex = elementColors.paceBaseHex { return Color(hex: hex) }
        return nil
    }
    private func previewWeeklyColor(percentage: Int) -> Color {
        if let hex = elementColors.weeklyBaseHex { return Color(hex: hex) ?? TerminalColors.usageLevel(percentage) }
        return TerminalColors.usageLevel(percentage)
    }
    private func previewExtraColor(percentage: Int) -> Color {
        if let hex = elementColors.extraUsageBaseHex { return Color(hex: hex) ?? TerminalColors.usageLevel(percentage) }
        return TerminalColors.usageLevel(percentage)
    }

    /// Preview view showing statusline with appropriate colors
    @ViewBuilder
    private var previewView: some View {
        let colorMode = SharedDataStore.shared.loadStatuslineColorMode()

        if colorMode == .colored || colorMode == .perElement {
            // Multi-color preview - each element gets its own color
            multiColorPreview
        } else {
            // Single/mono color preview — split at pace marker if step colors enabled
            let preview = generatePreview()
            if showPaceMarker && paceMarkerStepColors && showProgressBar && showUsage,
               let markerRange = preview.range(of: "┃") {
                let usage = profileManager.activeProfile?.claudeUsage
                let percentage = usage != nil ? Int(usage!.sessionPercentage) : 29
                let paceColor = previewPaceColor(percentage: percentage)
                HStack(spacing: 0) {
                    Text(String(preview[preview.startIndex..<markerRange.lowerBound]))
                        .foregroundColor(previewColor)
                    Text("┃")
                        .foregroundColor(paceColor)
                    Text(String(preview[markerRange.upperBound...]))
                        .foregroundColor(previewColor)
                }
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
            } else {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(previewColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Terminal-Matching Colors (ANSI standard)

    /// Colors matching ANSI standard terminal colors used in the bash statusline script
    private enum TerminalColors {
        static let blue = Color(red: 0/255, green: 0/255, blue: 238/255)
        static let green = Color(red: 0/255, green: 187/255, blue: 0/255)
        static let yellow = Color(red: 187/255, green: 187/255, blue: 0/255)
        static let magenta = Color(red: 187/255, green: 0/255, blue: 187/255)
        static let cyan = Color(red: 0/255, green: 187/255, blue: 187/255)
        static let gray = Color(red: 128/255, green: 128/255, blue: 128/255)

        // 6-tier pace marker colors (ANSI 256-color palette)
        static let paceComfortable = Color(red: 0/255, green: 175/255, blue: 0/255)
        static let paceOnTrack = Color(red: 0/255, green: 175/255, blue: 175/255)
        static let paceWarming = Color(red: 215/255, green: 175/255, blue: 0/255)
        static let pacePressing = Color(red: 255/255, green: 135/255, blue: 0/255)
        static let paceCritical = Color(red: 215/255, green: 0/255, blue: 0/255)
        static let paceRunaway = Color(red: 175/255, green: 95/255, blue: 255/255)

        // 10-level usage gradient (ANSI 256-color palette)
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

    /// Multi-color preview showing each element in different colors.
    /// Used for both `.colored` and `.perElement` modes.
    private var multiColorPreview: some View {
        let usage = profileManager.activeProfile?.claudeUsage
        let percentage = usage != nil ? Int(usage!.sessionPercentage) : 29
        let isPerElement = colorMode == .perElement
        let dirColor    = isPerElement ? previewDirectoryColor : TerminalColors.blue
        let branchColor = isPerElement ? previewBranchColor    : TerminalColors.green
        let modelColor  = isPerElement ? previewModelColor     : TerminalColors.yellow
        let profColor   = isPerElement ? previewProfileColor   : TerminalColors.magenta
        let ctxColor    = isPerElement ? previewContextColor   : TerminalColors.cyan
        let sepColor    = isPerElement ? previewSeparatorColor : TerminalColors.gray
        let usageColor  = isPerElement ? previewUsageColor(percentage: percentage) : TerminalColors.usageLevel(percentage)

        return HStack(spacing: 0) {
            if showDirectory {
                Text("claude-usage")
                    .foregroundColor(dirColor)
                if showBranch || showModel || showProfile || showContext || showUsage {
                    Text(" │ ").foregroundColor(sepColor)
                }
            }

            if showBranch {
                Text("⎇ main")
                    .foregroundColor(branchColor)
                if showModel || showProfile || showContext || showUsage {
                    Text(" │ ").foregroundColor(sepColor)
                }
            }

            if showModel {
                Text("Opus")
                    .foregroundColor(modelColor)
                if showProfile || showContext || showUsage {
                    Text(" │ ").foregroundColor(sepColor)
                }
            }

            if showProfile {
                let name = ProfileManager.shared.activeProfile?.name ?? "Profile"
                Text(name)
                    .foregroundColor(profColor)
                if showContext || showUsage {
                    Text(" │ ").foregroundColor(sepColor)
                }
            }

            if showContext {
                let ctxPrefix = showContextLabel ? "Ctx: " : ""
                if contextAsTokens {
                    Text("\(ctxPrefix)96K")
                        .foregroundColor(ctxColor)
                } else {
                    Text("\(ctxPrefix)48%")
                        .foregroundColor(ctxColor)
                }
                if showUsage {
                    Text(" │ ").foregroundColor(sepColor)
                }
            }

            if showUsage {
                let usagePrefix = showUsageLabel ? "Usage: " : ""
                Text(usagePrefix + "\(percentage)%")
                    .foregroundColor(usageColor)

                if showProgressBar {
                    let filledBlocks = max(0, min(10, (percentage + 5) / 10))
                    let emptyBlocks = 10 - filledBlocks

                    if showPaceMarker {
                        let markerPos = max(0, min(9, previewMarkerPosition))
                        let basePaceColor = previewPaceColor(percentage: percentage)
                        let paceColor = (isPerElement ? previewPaceOverrideColor(percentage: percentage) : nil) ?? basePaceColor
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

                if showResetTime {
                    let resetTimeString = formatResetTime(usage?.sessionResetTime)
                    let resetPrefix = showResetLabel ? " → Reset: " : " → "
                    Text(resetPrefix + resetTimeString)
                        .foregroundColor(usageColor)
                }
            }

            if showWeekly && showUsage {
                let usage = profileManager.activeProfile?.claudeUsage
                let weeklyPct = usage != nil ? Int(usage!.weeklyPercentage) : 45
                let weeklyColor = previewWeeklyColor(percentage: weeklyPct)
                if showDirectory || showBranch || showModel || showProfile || showContext || showUsage {
                    Text(" │ ").foregroundColor(TerminalColors.gray)
                }
                let weeklyPrefix = showWeeklyLabel ? "Weekly: " : ""
                Text("\(weeklyPrefix)\(weeklyPct)%")
                    .foregroundColor(weeklyColor)
                if showWeeklyBar {
                    let wFilled = max(0, min(10, (weeklyPct + 5) / 10))
                    let wEmpty = 10 - wFilled
                    let wBar = String(repeating: "▓", count: wFilled) + String(repeating: "░", count: wEmpty)
                    if showWeeklyPaceMarker {
                        let wMarkerPos = max(0, min(9, previewWeeklyMarkerPosition))
                        let wChars = Array(wBar)
                        Text(" " + String(wChars.prefix(wMarkerPos)))
                            .foregroundColor(weeklyColor)
                        Text("┃")
                            .foregroundColor(previewWeeklyPaceColor(percentage: weeklyPct))
                        Text(String(wChars.suffix(from: wMarkerPos + 1)))
                            .foregroundColor(weeklyColor)
                    } else {
                        Text(" \(wBar)").foregroundColor(weeklyColor)
                    }
                }
                if showWeeklyResetTime {
                    let weeklyResetString = formatWeeklyResetTime(usage?.weeklyResetTime)
                    Text(" → \(weeklyResetString)").foregroundColor(weeklyColor)
                }
            }

            if showExtraUsage && showUsage {
                if showDirectory || showBranch || showModel || showProfile || showContext || showUsage || (showWeekly && showUsage) {
                    Text(" │ ").foregroundColor(TerminalColors.gray)
                }
                if let claudeUsage = profileManager.activeProfile?.claudeUsage,
                   let costUsed = claudeUsage.costUsed,
                   let costLimit = claudeUsage.costLimit,
                   let costCurrency = claudeUsage.costCurrency,
                   costLimit > 0 {
                    let costPct = min(100, Int(costUsed / costLimit * 100))
                    let costColor = previewExtraColor(percentage: costPct)
                    Text(String(format: "%.2f %@", costUsed / 100.0, costCurrency))
                        .foregroundColor(costColor)
                } else {
                    Text("– USD").foregroundColor(TerminalColors.gray)
                }
            }

            if !showDirectory && !showBranch && !showModel && !showProfile && !showContext && !showUsage && !showWeekly && !showExtraUsage {
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

    /// Formats weekly reset time for preview display (weekday + time)
    private func formatWeeklyResetTime(_ date: Date?) -> String {
        guard let date = date else { return "Mon --:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = use24HourTime ? "EEE HH:mm" : "EEE h:mm a"
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
        case .perElement:
            return Color(hex: elementColors.directoryHex) ?? .purple
        }
    }

    /// Marker position for preview (0-9), based on real elapsed time or demo
    private var previewMarkerPosition: Int {
        if let usage = profileManager.activeProfile?.claudeUsage {
            let remaining = usage.sessionResetTime.timeIntervalSince(Date())
            if remaining > 0 && remaining < 18000 {
                let elapsed = 18000 - remaining
                return max(0, min(9, Int(round(elapsed * 10.0 / 18000.0))))
            }
        }
        return 6 // Demo: 60% elapsed
    }

    /// Marker position for weekly preview (0-9), based on real elapsed time or demo
    private var previewWeeklyMarkerPosition: Int {
        if let usage = profileManager.activeProfile?.claudeUsage {
            let remaining = usage.weeklyResetTime.timeIntervalSince(Date())
            if remaining > 0 && remaining < 604800 {
                let elapsed = 604800 - remaining
                return max(0, min(9, Int(round(elapsed * 10.0 / 604800.0))))
            }
        }
        return 3 // Demo: ~30% elapsed in weekly window
    }

    /// Pace color for the marker in preview, matching terminal ANSI colors
    private func previewPaceColor(percentage: Int) -> Color {
        guard paceMarkerStepColors else {
            return TerminalColors.usageLevel(percentage)
        }

        let elapsedFraction: Double
        if let usage = profileManager.activeProfile?.claudeUsage {
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

    /// Pace color for the weekly marker in preview, matching terminal ANSI colors
    private func previewWeeklyPaceColor(percentage: Int) -> Color {
        guard paceMarkerStepColors else {
            return TerminalColors.usageLevel(percentage)
        }

        let elapsedFraction: Double
        if let usage = profileManager.activeProfile?.claudeUsage {
            let remaining = usage.weeklyResetTime.timeIntervalSince(Date())
            if remaining > 0 && remaining < 604800 {
                elapsedFraction = (604800 - remaining) / 604800
            } else {
                elapsedFraction = 0.3
            }
        } else {
            elapsedFraction = 0.3
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
        guard showModel || showDirectory || showBranch || showContext || showUsage || showProfile || showWeekly || showExtraUsage else {
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
        SharedDataStore.shared.saveStatuslineShowModel(showModel)
        SharedDataStore.shared.saveStatuslineShowDirectory(showDirectory)
        SharedDataStore.shared.saveStatuslineShowBranch(showBranch)
        SharedDataStore.shared.saveStatuslineShowContext(showContext)
        SharedDataStore.shared.saveStatuslineContextAsTokens(contextAsTokens)
        SharedDataStore.shared.saveStatuslineShowUsage(showUsage)
        SharedDataStore.shared.saveStatuslineShowProgressBar(showProgressBar)
        SharedDataStore.shared.saveStatuslineShowPaceMarker(showPaceMarker)
        SharedDataStore.shared.saveStatuslinePaceMarkerStepColors(paceMarkerStepColors)
        SharedDataStore.shared.saveStatuslineShowResetTime(showResetTime)
        SharedDataStore.shared.saveStatuslineShowProfile(showProfile)
        SharedDataStore.shared.saveStatuslineUse24HourTime(use24HourTime)
        SharedDataStore.shared.saveStatuslineShowContextLabel(showContextLabel)
        SharedDataStore.shared.saveStatuslineShowUsageLabel(showUsageLabel)
        SharedDataStore.shared.saveStatuslineShowResetLabel(showResetLabel)
        SharedDataStore.shared.saveStatuslineShowWeekly(showWeekly)
        SharedDataStore.shared.saveStatuslineShowWeeklyBar(showWeeklyBar)
        SharedDataStore.shared.saveStatuslineShowWeeklyPaceMarker(showWeeklyPaceMarker)
        SharedDataStore.shared.saveStatuslineShowWeeklyResetTime(showWeeklyResetTime)
        SharedDataStore.shared.saveStatuslineShowWeeklyLabel(showWeeklyLabel)
        SharedDataStore.shared.saveStatuslineShowExtraUsage(showExtraUsage)

        do {
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
                showPaceMarker: showPaceMarker,
                paceMarkerStepColors: paceMarkerStepColors,
                showResetTime: showResetTime,
                use24HourTime: use24HourTime,
                showContextLabel: showContextLabel,
                showUsageLabel: showUsageLabel,
                showResetLabel: showResetLabel,
                colorMode: colorMode,
                singleColorHex: singleColorHex,
                showProfile: showProfile,
                profileName: profileName,
                showWeekly: showWeekly,
                showWeeklyBar: showWeeklyBar,
                showWeeklyPaceMarker: showWeeklyPaceMarker,
                showWeeklyResetTime: showWeeklyResetTime,
                showWeeklyLabel: showWeeklyLabel,
                showExtraUsage: showExtraUsage
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

        if showModel {
            parts.append("Opus")
        }

        if showProfile {
            let name = ProfileManager.shared.activeProfile?.name ?? "Profile"
            parts.append(name)
        }

        if showContext {
            let ctxPrefix = showContextLabel ? "Ctx: " : ""
            if contextAsTokens {
                parts.append("\(ctxPrefix)96K")
            } else {
                parts.append("\(ctxPrefix)48%")
            }
        }

        if showUsage {
            // Use real usage data if available
            let usage = profileManager.activeProfile?.claudeUsage
            let percentage = usage != nil ? Int(usage!.sessionPercentage) : 29

            var usageText = showUsageLabel ? "Usage: \(percentage)%" : "\(percentage)%"

            if showProgressBar {
                let filledBlocks = max(0, min(10, (percentage + 5) / 10))
                let emptyBlocks = 10 - filledBlocks
                var barChars = Array(String(repeating: "▓", count: filledBlocks) + String(repeating: "░", count: emptyBlocks))

                if showPaceMarker {
                    let markerPos = max(0, min(9, previewMarkerPosition))
                    barChars[markerPos] = "┃"
                }

                usageText += " \(String(barChars))"
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

        if showWeekly && showUsage {
            let usage = profileManager.activeProfile?.claudeUsage
            let weeklyPct = usage != nil ? Int(usage!.weeklyPercentage) : 45
            var weeklyText = showWeeklyLabel ? "Weekly: \(weeklyPct)%" : "\(weeklyPct)%"

            if showWeeklyBar {
                let wFilled = max(0, min(10, (weeklyPct + 5) / 10))
                let wEmpty = 10 - wFilled
                var wChars = Array(String(repeating: "▓", count: wFilled) + String(repeating: "░", count: wEmpty))
                if showWeeklyPaceMarker {
                    let wMarkerPos = max(0, min(9, previewWeeklyMarkerPosition))
                    wChars[wMarkerPos] = "┃"
                }
                weeklyText += " \(String(wChars))"
            }

            if showWeeklyResetTime {
                let wResetStr = formatWeeklyResetTime(usage?.weeklyResetTime)
                weeklyText += " → \(wResetStr)"
            }

            parts.append(weeklyText)
        }

        if showExtraUsage && showUsage {
            if let claudeUsage = profileManager.activeProfile?.claudeUsage,
               let costUsed = claudeUsage.costUsed,
               let costLimit = claudeUsage.costLimit,
               let costCurrency = claudeUsage.costCurrency,
               costLimit > 0 {
                parts.append(String(format: "%.2f %@", costUsed / 100.0, costCurrency))
            } else {
                parts.append("– USD")
            }
        }

        return parts.isEmpty ? "claudecode.preview_no_components".localized : parts.joined(separator: " │ ")
    }
}

// MARK: - Per-Element Color Rows

/// A single row showing a label and a `ColorPicker` for a required statusline element color.
///
/// Used inside the "Element Colors" disclosure group in `ClaudeCodeView`
/// when `StatuslineColorMode` is `.perElement`.
private struct ElementColorRow: View {
    let label: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(label)
                .font(DesignTokens.Typography.body)
                .foregroundColor(.primary)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex) ?? .blue },
                set: { hex = $0.toHex() ?? hex }
            ))
            .labelsHidden()
        }
    }
}

/// A row with a toggle and an optional `ColorPicker` for a statusline element
/// that supports dynamic multi-level coloring (usage gradient, pace tiers).
///
/// When the toggle is off the binding value is `nil`, which tells the bash script
/// to use the default dynamic behavior (10-level gradient or 6-tier pace colors).
/// When on, the chosen color overrides all levels with a single fixed color.
private struct ElementColorRowOptional: View {
    let label: String
    let description: String
    @Binding var hex: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: Binding(
                    get: { hex != nil },
                    set: { enabled in hex = enabled ? "#00BB00" : nil }
                )) {
                    Text(label)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(.primary)
                }
                .toggleStyle(.switch)

                if hex != nil {
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: hex!) ?? .green },
                        set: { hex = $0.toHex() ?? hex }
                    ))
                    .labelsHidden()
                }
            }
            Text(description)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

#Preview {
    ClaudeCodeView()
        .frame(width: 520, height: 600)
}
