//
//  MediumWidgetView.swift
//  Claude Usage Widget
//
//  Medium widget showing configurable metric pair with progress bars
//

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let usage = entry.usage {
            VStack(spacing: WidgetDesign.Spacing.sectionSpacing) {
                // Header row (per Apple HIG - medium widgets should have headers)
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: WidgetDesign.Typography.iconMedium))
                        .foregroundColor(.purple)
                    Text("Claude Usage")
                        .font(.system(size: WidgetDesign.Typography.headerTitle, weight: .semibold))
                    Spacer()
                    Text(lastUpdatedText(usage.lastUpdated))
                        .font(.system(size: WidgetDesign.Typography.timestamp))
                        .foregroundColor(secondaryTextColor)
                }

                // Usage cards with independent metric selection
                HStack(spacing: WidgetDesign.Spacing.cardSpacing) {
                    // Left card
                    UsageCard(
                        metric: entry.mediumLeftMetric,
                        usage: usage,
                        colorMode: entry.colorMode,
                        customColorHex: entry.customColorHex,
                        showPaceMarker: entry.showPaceMarker,
                        usePaceColoring: entry.usePaceColoring
                    )

                    // Right card
                    UsageCard(
                        metric: entry.mediumRightMetric,
                        usage: usage,
                        colorMode: entry.colorMode,
                        customColorHex: entry.customColorHex,
                        showPaceMarker: entry.showPaceMarker,
                        usePaceColoring: entry.usePaceColoring
                    )
                }
            }
            .padding(WidgetDesign.Spacing.outerPadding)
        } else {
            noDataView
        }
    }

    // MARK: - Helper Methods

    private func lastUpdatedText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: - Colors

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: WidgetDesign.NoData.iconMedium))
                .foregroundColor(secondaryTextColor)

            Text("No Data Available")
                .font(.system(size: WidgetDesign.NoData.titleMedium, weight: .medium))
                .foregroundColor(secondaryTextColor)

            Text("Open Claude Usage app to sync data")
                .font(.system(size: WidgetDesign.NoData.subtitleMedium))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(WidgetDesign.Spacing.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Usage Card (Configurable)

struct UsageCard: View {
    let metric: WidgetSmallMetric
    let usage: WidgetUsageData
    let colorMode: WidgetColorDisplayMode
    let customColorHex: String
    var showPaceMarker: Bool = true
    var usePaceColoring: Bool = false

    private var metricData: MetricDisplayData {
        getMetricData(for: metric, usage: usage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack {
                Image(systemName: metric.icon)
                    .font(.system(size: WidgetDesign.Typography.iconSmall))
                    .foregroundColor(statusColor)
                Text(metric.displayName)
                    .font(.system(size: WidgetDesign.Typography.cardTitle, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                Spacer()
            }

            // Percentage
            Text("\(Int(metricData.percentage.rounded()))%")
                .font(.system(size: WidgetDesign.Typography.percentageMedium, weight: .bold, design: .rounded))
                .foregroundColor(statusColor)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(WidgetDesign.Colors.glassProgressBg))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(metricData.percentage / 100, 1.0))

                    // Pace marker dot on bottom edge of progress bar
                    if showPaceMarker, let paceData = usage.paceData(for: metric) {
                        let tickX = geometry.size.width * paceData.elapsed
                        Circle()
                            .fill(paceData.pace.color)
                            .frame(width: 5, height: 5)
                            .position(x: tickX, y: WidgetDesign.Spacing.progressHeight)
                    }
                }
            }
            .frame(height: WidgetDesign.Spacing.progressHeight)
            .padding(.bottom, 3)

            // Reset time or cost (for extra metric)
            Text(subtitleText(for: metric, metricData: metricData, usage: usage))
                .font(.system(size: WidgetDesign.Typography.timestamp, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(WidgetDesign.Spacing.cardPadding)
        .widgetCardBackground()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metric Data Helper

    private struct MetricDisplayData {
        let percentage: Double
        let resetTime: Date
        let status: WidgetStatusLevel
    }

    private func getMetricData(for metric: WidgetSmallMetric, usage: WidgetUsageData) -> MetricDisplayData {
        switch metric {
        case .session:
            return MetricDisplayData(
                percentage: usage.sessionPercentage,
                resetTime: usage.sessionResetTime,
                status: usage.statusLevel
            )
        case .weekly:
            return MetricDisplayData(
                percentage: usage.weeklyPercentage,
                resetTime: usage.weeklyResetTime,
                status: usage.weeklyStatusLevel
            )
        case .opus:
            return MetricDisplayData(
                percentage: usage.opusPercentage,
                resetTime: usage.weeklyResetTime,
                status: WidgetStatusLevel.from(percentage: usage.opusPercentage)
            )
        case .sonnet:
            return MetricDisplayData(
                percentage: usage.sonnetPercentage,
                resetTime: usage.weeklyResetTime,
                status: WidgetStatusLevel.from(percentage: usage.sonnetPercentage)
            )
        case .extra:
            return MetricDisplayData(
                percentage: usage.extraPercentage ?? 0.0,
                resetTime: usage.weeklyResetTime,  // Extra usage typically resets weekly
                status: usage.extraStatusLevel
            )
        }
    }

    // MARK: - Colors

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private var statusColor: Color {
        let elapsed: Double? = usePaceColoring
            ? usage.paceData(for: metric)?.elapsed
            : nil
        return WidgetDataProvider.shared.colorForUsage(
            metricData.percentage,
            mode: colorMode,
            customColorHex: customColorHex,
            elapsedFraction: elapsed
        )
    }

    private func subtitleText(for metric: WidgetSmallMetric, metricData: MetricDisplayData, usage: WidgetUsageData) -> String {
        // For extra metric, show cost amount
        if metric == .extra {
            return usage.formattedExtraUsed ?? "$0.00"
        }
        // Session uses compact "Resets X:XXPM" format (no day prefix)
        if metric == .session {
            return WidgetDateFormatter.sessionResetTimeString(from: metricData.resetTime)
        }
        // All other metrics show full reset time with day
        return WidgetDateFormatter.resetTimeString(from: metricData.resetTime)
    }
}
