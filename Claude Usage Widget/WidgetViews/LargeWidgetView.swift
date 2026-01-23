//
//  LargeWidgetView.swift
//  Claude Usage Widget
//
//  Large widget showing full dashboard with session, weekly, opus, and API usage
//

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let usage = entry.usage {
            VStack(spacing: WidgetDesign.Spacing.sectionSpacing) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: WidgetDesign.Typography.headerTitle))
                        .foregroundColor(.purple)
                    Text("Claude Usage")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(lastUpdatedText(usage.lastUpdated))
                        .font(.system(size: WidgetDesign.Typography.timestamp))
                        .foregroundColor(secondaryTextColor)
                }

                Divider()
                    .background(dividerColor)

                // Main metrics grid - optimized for ~364x364 widget
                // Show extra usage if any metric is at 0% and extra data is available
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: WidgetDesign.Spacing.cardSpacing),
                    GridItem(.flexible(), spacing: WidgetDesign.Spacing.cardSpacing)
                ], spacing: WidgetDesign.Spacing.cardSpacing) {
                    // Session Usage
                    MetricTile(
                        title: "Session",
                        percentage: usage.sessionPercentage,
                        subtitle: WidgetDateFormatter.shortTimeString(from: usage.sessionResetTime),
                        icon: "clock.fill",
                        colorMode: entry.colorMode,
                        customColorHex: entry.customColorHex
                    )

                    // Weekly Usage
                    MetricTile(
                        title: "Weekly",
                        percentage: usage.weeklyPercentage,
                        subtitle: WidgetDateFormatter.shortTimeString(from: usage.weeklyResetTime),
                        icon: "calendar",
                        colorMode: entry.colorMode,
                        customColorHex: entry.customColorHex
                    )

                    // Opus Usage - show Extra if Opus is 0% and extra data exists
                    if usage.opusPercentage > 0 {
                        MetricTile(
                            title: "Opus",
                            percentage: usage.opusPercentage,
                            subtitle: WidgetDateFormatter.shortTimeString(from: usage.weeklyResetTime),
                            icon: "star.fill",
                                colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    } else if let extraPercentage = usage.extraPercentage {
                        MetricTile(
                            title: "Extra",
                            percentage: extraPercentage,
                            subtitle: usage.formattedExtraUsed ?? "$0.00",
                            icon: "dollarsign.circle.fill",
                            colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    } else {
                        MetricTile(
                            title: "Opus",
                            percentage: usage.opusPercentage,
                            subtitle: WidgetDateFormatter.shortTimeString(from: usage.weeklyResetTime),
                            icon: "star.fill",
                                colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    }

                    // Sonnet Usage - show Extra if Sonnet is 0% and extra data exists (and wasn't shown for Opus)
                    if usage.sonnetPercentage > 0 {
                        MetricTile(
                            title: "Sonnet",
                            percentage: usage.sonnetPercentage,
                            subtitle: WidgetDateFormatter.shortTimeString(from: usage.weeklyResetTime),
                            icon: "bolt.fill",
                                colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    } else if let extraPercentage = usage.extraPercentage, usage.opusPercentage > 0 {
                        // Only show extra here if we didn't already show it for Opus
                        MetricTile(
                            title: "Extra",
                            percentage: extraPercentage,
                            subtitle: usage.formattedExtraUsed ?? "$0.00",
                            icon: "dollarsign.circle.fill",
                            colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    } else {
                        MetricTile(
                            title: "Sonnet",
                            percentage: usage.sonnetPercentage,
                            subtitle: WidgetDateFormatter.shortTimeString(from: usage.weeklyResetTime),
                            icon: "bolt.fill",
                                colorMode: entry.colorMode,
                            customColorHex: entry.customColorHex
                        )
                    }
                }

                // API Usage (if available)
                if let apiUsage = entry.apiUsage {
                    Divider()
                        .background(dividerColor)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: WidgetDesign.Typography.iconSmall))
                                    .foregroundColor(.blue)
                                Text("API Credits")
                                    .font(.system(size: WidgetDesign.Typography.iconMedium, weight: .medium))
                                    .foregroundColor(secondaryTextColor)
                            }

                            Text("\(apiUsage.formattedUsed) / \(apiUsage.formattedTotal)")
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Spacer()

                        // API progress ring
                        ZStack {
                            Circle()
                                .stroke(ringBackgroundColor, lineWidth: 5)

                            Circle()
                                .trim(from: 0, to: min(apiUsage.usagePercentage / 100, 1.0))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))

                            Text("\(Int(apiUsage.usagePercentage))%")
                                .font(.system(size: WidgetDesign.Typography.iconMedium, weight: .bold, design: .rounded))
                        }
                        .frame(width: 48, height: 48)
                    }
                }
            }
            .padding(WidgetDesign.Spacing.outerPadding)
        } else {
            noDataView
        }
    }

    // MARK: - Colors

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private var dividerColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassDivider)
    }

    private var ringBackgroundColor: Color {
        Color.white.opacity(0.15)  // Very subtle background for ring track
    }

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: WidgetDesign.NoData.iconLarge))
                .foregroundColor(secondaryTextColor)

            Text("No Usage Data")
                .font(.system(size: WidgetDesign.NoData.titleLarge, weight: .semibold))
                .foregroundColor(.primary)

            Text("Open the Claude Usage app to sync your data and enable widget display.")
                .font(.system(size: WidgetDesign.NoData.subtitleLarge))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(WidgetDesign.Spacing.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lastUpdatedText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func statusLevel(for percentage: Double) -> WidgetStatusLevel {
        switch percentage {
        case 0..<50:
            return .safe
        case 50..<80:
            return .moderate
        default:
            return .critical
        }
    }

}

struct MetricTile: View {
    let title: String
    let percentage: Double
    let subtitle: String
    let icon: String
    let colorMode: WidgetColorDisplayMode
    let customColorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: WidgetDesign.Typography.iconSmall))
                    .foregroundColor(statusColor)
                Text(title)
                    .font(.system(size: WidgetDesign.Typography.iconMedium, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }

            Text("\(Int(percentage.rounded()))%")
                .font(.system(size: WidgetDesign.Typography.percentageMedium, weight: .bold, design: .rounded))
                .foregroundColor(statusColor)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressBackgroundColor)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(height: WidgetDesign.Spacing.progressHeight)

            Text(subtitle)
                .font(.system(size: WidgetDesign.Typography.timestamp))
                .foregroundColor(secondaryTextColor)
        }
        .padding(WidgetDesign.Spacing.cardPadding)
        .background(tileBackground)
        .cornerRadius(WidgetDesign.Spacing.cardCornerRadius)
    }

    // MARK: - Colors

    private var tileBackground: some View {
        // Use very subtle white tint for glass - maintains desktop transparency
        Color.white.opacity(0.05)
    }

    private var progressBackgroundColor: Color {
        Color.white.opacity(0.15)  // Very subtle background for progress track
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private var statusColor: Color {
        return WidgetDataProvider.shared.colorForUsage(
            percentage,
            mode: colorMode,
            customColorHex: customColorHex
        )
    }
}
