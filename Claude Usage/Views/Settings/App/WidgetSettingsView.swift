//
//  WidgetSettingsView.swift
//  Claude Usage - Widget Appearance Settings
//
//  Configure desktop widget appearance including glass/standard styles
//  and content customization
//

import SwiftUI
import WidgetKit

// MARK: - Widget Preview Design Tokens

/// Design tokens for widget previews (mirrors WidgetDesign in widget extension)
private enum PreviewDesign {
    enum Typography {
        static let percentageLarge: CGFloat = 28
        static let percentageMedium: CGFloat = 26
        static let headerTitle: CGFloat = 14
        static let cardTitle: CGFloat = 13
        static let subtitle: CGFloat = 11
        static let timestamp: CGFloat = 10
        static let iconSmall: CGFloat = 11
        static let iconMedium: CGFloat = 12
    }

    enum Spacing {
        static let outerPadding: CGFloat = 8
        static let cardPadding: CGFloat = 10
        static let cardCornerRadius: CGFloat = 10
        static let progressHeight: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let cardSpacing: CGFloat = 10
    }

    enum Ring {
        static let lineWidth: CGFloat = 8
        static let size: CGFloat = 80  // Scaled down for preview
    }

    enum Colors {
        static let glassCardBg: Double = 0.06
        static let glassProgressBg: Double = 0.12
        static let glassSecondaryText: Double = 0.6
        static let standardCardBg: Double = 0.08
        static let standardProgressBg: Double = 0.2
    }
}

/// Widget appearance and style settings
struct WidgetSettingsView: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var selectedSmallMetric: SmallWidgetMetric = SharedDataStore.shared.loadSmallWidgetMetric()
    @State private var selectedColorMode: WidgetColorMode = SharedDataStore.shared.loadWidgetColorMode()
    @State private var singleColor: Color = Color(hex: SharedDataStore.shared.loadWidgetSingleColorHex()) ?? .cyan
    @State private var extraUsageFormat: ExtraUsageDisplayFormat = SharedDataStore.shared.loadExtraUsageDisplayFormat()

    // Medium widget individual metric selection
    @State private var mediumLeftMetric: SmallWidgetMetric = SharedDataStore.shared.loadMediumWidgetLeftMetric()
    @State private var mediumRightMetric: SmallWidgetMetric = SharedDataStore.shared.loadMediumWidgetRightMetric()

    // Actual usage data for previews
    @State private var previewUsage: ClaudeUsage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Page Header
                SettingsPageHeader(
                    title: "Widgets",
                    subtitle: "Customize the appearance and content of your desktop widgets"
                )

                formatAndColorSection
                smallWidgetSection
                mediumWidgetSection
                aboutWidgetsSection

                Spacer()
            }
            .padding()
        }
        .onAppear {
            // Load actual usage data for previews
            if let activeProfile = profileManager.activeProfile {
                previewUsage = activeProfile.claudeUsage
            }
        }
        .onChange(of: profileManager.activeProfile?.claudeUsage) { _, newUsage in
            // Update preview when usage changes
            previewUsage = newUsage
        }
    }

    // MARK: - View Sections

    private var formatAndColorSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            extraUsageFormatCard
            widgetColorsCard
        }
    }

    private var extraUsageFormatCard: some View {
        SettingsSectionCard(
            title: "Extra Usage Format",
            subtitle: "Choose how to display cost-based usage"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach([ExtraUsageDisplayFormat.percentage, .currency, .both], id: \.self) { format in
                    Button {
                        extraUsageFormat = format
                        saveExtraUsageFormat(format)
                    } label: {
                        HStack {
                            Image(systemName: extraUsageFormat == format ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(extraUsageFormat == format ? .accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)

                                Text(format.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var widgetColorsCard: some View {
        SettingsSectionCard(
            title: "Widget Colors",
            subtitle: "Choose color display mode"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach([WidgetColorMode.multiColor, .monochrome, .singleColor], id: \.self) { mode in
                    Button {
                        selectedColorMode = mode
                        saveColorMode(mode)
                    } label: {
                        HStack {
                            Image(systemName: selectedColorMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedColorMode == mode ? .accentColor : .secondary)

                            Image(systemName: mode.icon)
                                .font(.system(size: 14))
                                .foregroundColor(iconColorForMode(mode))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)

                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }

                if selectedColorMode == .singleColor {
                    colorPickerRow
                }
            }
        }
    }

    private var colorPickerRow: some View {
        HStack {
            Spacer().frame(width: 20)

            ColorPicker("Choose Color", selection: Binding(
                get: { singleColor },
                set: { newColor in
                    singleColor = newColor
                    SharedDataStore.shared.saveWidgetSingleColorHex(newColor.toHex() ?? "#00BFFF")
                    refreshWidgets()
                }
            ))
            .labelsHidden()

            Text("Custom widget color")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var smallWidgetSection: some View {
        SettingsSectionCard(
            title: "Small Widget",
            subtitle: "Choose which metric to display"
        ) {
            HStack(alignment: .top, spacing: 16) {
                SmallWidgetPreview(
                    metric: selectedSmallMetric,
                    colorMode: selectedColorMode,
                    customColor: singleColor,
                    usage: previewUsage
                )

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SmallWidgetMetric.allCases, id: \.self) { metric in
                        MetricOptionRow(
                            metric: metric,
                            isSelected: selectedSmallMetric == metric,
                            onSelect: {
                                selectedSmallMetric = metric
                                saveSmallMetric(metric)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var mediumWidgetSection: some View {
        SettingsSectionCard(
            title: "Medium Widget",
            subtitle: "Choose which two metrics to display"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MediumWidgetPreview(
                    leftMetric: mediumLeftMetric,
                    rightMetric: mediumRightMetric,
                    colorMode: selectedColorMode,
                    customColor: singleColor,
                    usage: previewUsage
                )
                .frame(maxWidth: .infinity)

                mediumMetricPickers
            }
        }
    }

    private var mediumMetricPickers: some View {
        HStack(spacing: 12) {
            metricPicker(
                title: "Left Metric",
                selectedMetric: mediumLeftMetric,
                onSelect: { metric in
                    mediumLeftMetric = metric
                    updateMediumLayout()
                }
            )

            metricPicker(
                title: "Right Metric",
                selectedMetric: mediumRightMetric,
                onSelect: { metric in
                    mediumRightMetric = metric
                    updateMediumLayout()
                }
            )
        }
    }

    private func metricPicker(title: String, selectedMetric: SmallWidgetMetric, onSelect: @escaping (SmallWidgetMetric) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Menu {
                ForEach(SmallWidgetMetric.allCases, id: \.self) { metric in
                    Button {
                        onSelect(metric)
                    } label: {
                        HStack {
                            Image(systemName: metric.icon)
                            Text(metric.displayName)
                            if selectedMetric == metric {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedMetric.icon)
                        .font(.system(size: 12))
                        .foregroundColor(metricColor(selectedMetric))
                        .frame(width: 16)
                    Text(selectedMetric.displayName)
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutWidgetsSection: some View {
        SettingsSectionCard(
            title: "About Widgets",
            subtitle: "How to add widgets to your desktop"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(
                    icon: "plus.rectangle.on.rectangle",
                    title: "Add Widget",
                    description: "Right-click on your desktop and select \"Edit Widgets\" to add Claude Usage widgets"
                )

                Divider()

                InfoRow(
                    icon: "square.resize",
                    title: "Widget Sizes",
                    description: "Available in small (single metric), medium (two metrics), and large (full dashboard) sizes"
                )

                Divider()

                InfoRow(
                    icon: "arrow.clockwise",
                    title: "Refresh Rate",
                    description: "Widgets refresh instantly when the app is active, or automatically every 15 minutes when the app is closed"
                )
            }
        }
    }

    // MARK: - Save Methods

    private func saveSmallMetric(_ metric: SmallWidgetMetric) {
        SharedDataStore.shared.saveSmallWidgetMetric(metric)
        refreshWidgets()
        LoggingService.shared.log("Small widget metric changed to: \(metric.displayName)")
    }

    private func saveColorMode(_ mode: WidgetColorMode) {
        SharedDataStore.shared.saveWidgetColorMode(mode)
        refreshWidgets()
        LoggingService.shared.log("Widget color mode changed to: \(mode.displayName)")
    }

    private func saveExtraUsageFormat(_ format: ExtraUsageDisplayFormat) {
        SharedDataStore.shared.saveExtraUsageDisplayFormat(format)
        refreshWidgets()
        LoggingService.shared.log("Extra usage format changed to: \(format.displayName)")
    }

    private func iconColorForMode(_ mode: WidgetColorMode) -> Color {
        switch mode {
        case .multiColor:
            return .purple
        case .monochrome:
            return .primary
        case .singleColor:
            return singleColor
        }
    }

    /// Returns color for a given metric
    private func metricColor(_ metric: SmallWidgetMetric) -> Color {
        switch metric {
        case .session:
            return .green
        case .weekly:
            return .blue
        case .opus:
            return .purple
        case .sonnet:
            return .orange
        case .extra:
            return .cyan
        }
    }

    /// Saves medium widget metrics when selection changes
    private func updateMediumLayout() {
        SharedDataStore.shared.saveMediumWidgetLeftMetric(mediumLeftMetric)
        SharedDataStore.shared.saveMediumWidgetRightMetric(mediumRightMetric)
        refreshWidgets()
        LoggingService.shared.log("Medium widget metrics changed to: \(mediumLeftMetric.displayName) + \(mediumRightMetric.displayName)")
    }

    private func refreshWidgets() {
        if #available(macOS 14.0, *) {
            // Small delay to ensure UserDefaults sync propagates across processes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

// MARK: - Metric Option Row (Compact)

private struct MetricOptionRow: View {
    let metric: SmallWidgetMetric
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 14))
                    .foregroundColor(metricColor)
                    .frame(width: 20)

                Text(metric.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var metricColor: Color {
        switch metric {
        case .session:
            return .green
        case .weekly:
            return .blue
        case .opus:
            return .purple
        case .sonnet:
            return .orange
        case .extra:
            return .cyan
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Small Widget Preview

private struct SmallWidgetPreview: View {
    let metric: SmallWidgetMetric
    let colorMode: WidgetColorMode
    let customColor: Color
    let usage: ClaudeUsage?

    // Computed data from real usage or fallback to sample
    private var previewPercentage: Double {
        guard let usage = usage else { return 45.0 }
        switch metric {
        case .session: return usage.sessionPercentage
        case .weekly: return usage.weeklyPercentage
        case .opus: return usage.opusWeeklyPercentage
        case .sonnet: return usage.sonnetWeeklyPercentage
        case .extra:
            if let used = usage.costUsed, let limit = usage.costLimit, limit > 0 {
                return (used / limit) * 100.0
            }
            return 0.0
        }
    }

    private var previewResetTime: Date {
        guard let usage = usage else { return Date().addingTimeInterval(3600 * 2) }
        switch metric {
        case .session: return usage.sessionResetTime
        case .weekly, .opus, .sonnet, .extra: return usage.weeklyResetTime
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(ringBackgroundColor, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: previewPercentage / 100)
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(previewPercentage))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)

                    Text(metric.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .frame(width: 100, height: 100)

            // Reset time
            Text(formatResetTime(previewResetTime))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 155, height: 155)  // Close to actual macOS small widget size
        .background(previewBackground)
        .cornerRadius(20)
    }

    private var ringBackgroundColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassProgressBg)
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassSecondaryText)
    }

    private var statusColor: Color {
        colorForUsage(previewPercentage, mode: colorMode, customColor: customColor)
    }

    private var previewBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
    }

    private func formatResetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Resets Today' h:mma"
        return formatter.string(from: date.roundedToNearestMinute())
    }
}

// MARK: - Medium Widget Preview

private struct MediumWidgetPreview: View {
    let leftMetric: SmallWidgetMetric
    let rightMetric: SmallWidgetMetric
    let colorMode: WidgetColorMode
    let customColor: Color
    let usage: ClaudeUsage?

    var body: some View {
        VStack(spacing: 10) {
            // Header row
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text("Claude Usage")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Updated 5m ago")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryTextColor)
            }

            // Usage cards
            HStack(spacing: 10) {
                PreviewUsageCard(
                    metric: leftMetric,
                    percentage: percentageFor(leftMetric),
                    colorMode: colorMode,
                    customColor: customColor
                )
                PreviewUsageCard(
                    metric: rightMetric,
                    percentage: percentageFor(rightMetric),
                    colorMode: colorMode,
                    customColor: customColor
                )
            }
        }
        .padding(12)
        .frame(width: 329, height: 155)  // Actual macOS medium widget size
        .background(previewBackground)
        .cornerRadius(20)
    }

    private func percentageFor(_ metric: SmallWidgetMetric) -> Double {
        guard let usage = usage else {
            // Fallback to sample data
            switch metric {
            case .session: return 45.0
            case .weekly: return 32.0
            case .opus: return 28.0
            case .sonnet: return 35.0
            case .extra: return 22.5
            }
        }

        // Use real data
        switch metric {
        case .session: return usage.sessionPercentage
        case .weekly: return usage.weeklyPercentage
        case .opus: return usage.opusWeeklyPercentage
        case .sonnet: return usage.sonnetWeeklyPercentage
        case .extra:
            if let used = usage.costUsed, let limit = usage.costLimit, limit > 0 {
                return (used / limit) * 100.0
            }
            return 0.0
        }
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassSecondaryText)
    }

    private var previewBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
    }
}

// MARK: - Preview Usage Card

private struct PreviewUsageCard: View {
    let metric: SmallWidgetMetric
    let percentage: Double
    let colorMode: WidgetColorMode
    let customColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.system(size: 11))
                    .foregroundColor(statusColor)
                Text(metric.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }

            // Percentage
            Text("\(Int(percentage))%")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(statusColor)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressBackgroundColor)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * (percentage / 100))
                }
            }
            .frame(height: 8)

            // Reset time
            Text("Resets Today 4PM")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
        }
        .padding(10)
        .background(cardBackgroundColor)
        .cornerRadius(10)
        .frame(maxWidth: .infinity)
    }

    private var cardBackgroundColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassCardBg)
    }

    private var progressBackgroundColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassProgressBg)
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(PreviewDesign.Colors.glassSecondaryText)
    }

    private var statusColor: Color {
        colorForUsage(percentage, mode: colorMode, customColor: customColor)
    }
}

// MARK: - Color Helpers

/// Returns color for usage percentage based on color mode
private func colorForUsage(_ percentage: Double, mode: WidgetColorMode, customColor: Color) -> Color {
    switch mode {
    case .multiColor:
        // Threshold-based colors (matching menu bar)
        switch percentage {
        case 0..<50:
            return SettingsColors.usageLow       // Green
        case 50..<80:
            return SettingsColors.usageHigh      // Orange
        default: // 80%+
            return SettingsColors.usageCritical  // Red
        }
    case .monochrome:
        return .primary  // Adaptive to system theme
    case .singleColor:
        return customColor
    }
}

// MARK: - Preview

#Preview {
    WidgetSettingsView()
        .frame(width: 520, height: 900)
}
