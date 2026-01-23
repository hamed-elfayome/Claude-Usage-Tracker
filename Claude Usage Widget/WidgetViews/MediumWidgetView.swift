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
                        customColorHex: entry.customColorHex
                    )

                    // Right card
                    UsageCard(
                        metric: entry.mediumRightMetric,
                        usage: usage,
                        colorMode: entry.colorMode,
                        customColorHex: entry.customColorHex
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
                        .fill(progressBackgroundColor)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(metricData.percentage / 100, 1.0))
                }
            }
            .frame(height: WidgetDesign.Spacing.progressHeight)

            // Reset time or cost (for extra metric)
            Text(subtitleText(for: metric, metricData: metricData, usage: usage))
                .font(.system(size: WidgetDesign.Typography.timestamp, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(WidgetDesign.Spacing.cardPadding)
        .background(cardBackground)
        .cornerRadius(WidgetDesign.Spacing.cardCornerRadius)
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
                status: statusLevel(for: usage.opusPercentage)
            )
        case .sonnet:
            return MetricDisplayData(
                percentage: usage.sonnetPercentage,
                resetTime: usage.weeklyResetTime,
                status: statusLevel(for: usage.sonnetPercentage)
            )
        case .extra:
            return MetricDisplayData(
                percentage: usage.extraPercentage ?? 0.0,
                resetTime: usage.weeklyResetTime,  // Extra usage typically resets weekly
                status: usage.extraStatusLevel
            )
        }
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

    // MARK: - Colors

    private var cardBackground: some View {
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
            metricData.percentage,
            mode: colorMode,
            customColorHex: customColorHex
        )
    }

    private func subtitleText(for metric: WidgetSmallMetric, metricData: MetricDisplayData, usage: WidgetUsageData) -> String {
        // For extra metric, show cost amount
        if metric == .extra {
            return usage.formattedExtraUsed ?? "$0.00"
        }
        // For all other metrics, show reset time
        return WidgetDateFormatter.resetTimeString(from: metricData.resetTime)
    }
}
