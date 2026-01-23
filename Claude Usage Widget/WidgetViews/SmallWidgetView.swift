//
//  SmallWidgetView.swift
//  Claude Usage Widget
//
//  Compact widget showing single configurable metric with circular progress
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let usage = entry.usage {
            let metricData = getMetricData(for: entry.smallMetric, usage: usage)

            VStack(spacing: 10) {
                // Circular progress indicator - sized for ~170x170 widget
                ZStack {
                    Circle()
                        .stroke(ringBackgroundColor, lineWidth: WidgetDesign.Ring.lineWidth)

                    Circle()
                        .trim(from: 0, to: min(metricData.percentage / 100, 1.0))
                        .stroke(
                            statusColor(for: metricData.percentage),
                            style: StrokeStyle(lineWidth: WidgetDesign.Ring.lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: metricData.percentage)

                    VStack(spacing: 0) {
                        Text("\(Int(metricData.percentage.rounded()))%")
                            .font(.system(size: WidgetDesign.Typography.percentageLarge, weight: .bold, design: .rounded))
                            .foregroundColor(statusColor(for: metricData.percentage))

                        Text(metricData.label)
                            .font(.system(size: WidgetDesign.Typography.subtitle, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .frame(width: WidgetDesign.Ring.size, height: WidgetDesign.Ring.size)

                // Reset time or extra usage info (based on metric and format)
                Text(subtitleText(for: entry.smallMetric, metricData: metricData, usage: usage, format: entry.extraUsageFormat))
                    .font(.system(size: WidgetDesign.Typography.subtitle, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(WidgetDesign.Spacing.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            noDataView
        }
    }

    // MARK: - Metric Data Helper

    private struct MetricDisplayData {
        let percentage: Double
        let resetTime: Date
        let status: WidgetStatusLevel
        let label: String
    }

    private func getMetricData(for metric: WidgetSmallMetric, usage: WidgetUsageData) -> MetricDisplayData {
        switch metric {
        case .session:
            return MetricDisplayData(
                percentage: usage.sessionPercentage,
                resetTime: usage.sessionResetTime,
                status: usage.statusLevel,
                label: "Session"
            )
        case .weekly:
            return MetricDisplayData(
                percentage: usage.weeklyPercentage,
                resetTime: usage.weeklyResetTime,
                status: usage.weeklyStatusLevel,
                label: "Weekly"
            )
        case .opus:
            return MetricDisplayData(
                percentage: usage.opusPercentage,
                resetTime: usage.weeklyResetTime,
                status: statusLevel(for: usage.opusPercentage),
                label: "Opus"
            )
        case .sonnet:
            return MetricDisplayData(
                percentage: usage.sonnetPercentage,
                resetTime: usage.weeklyResetTime,
                status: statusLevel(for: usage.sonnetPercentage),
                label: "Sonnet"
            )
        case .extra:
            return MetricDisplayData(
                percentage: usage.extraPercentage ?? 0.0,
                resetTime: usage.weeklyResetTime,  // Extra usage typically resets weekly
                status: usage.extraStatusLevel,
                label: "Extra"
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

    private func subtitleText(for metric: WidgetSmallMetric, metricData: MetricDisplayData, usage: WidgetUsageData, format: ExtraUsageDisplayFormat) -> String {
        // For non-extra metrics, always show reset time (compact for small widget)
        guard metric == .extra else {
            return WidgetDateFormatter.compactResetTimeString(from: metricData.resetTime)
        }

        // For extra usage, customize based on format preference
        switch format {
        case .percentage:
            // Show reset time (percentage already in main display)
            return WidgetDateFormatter.compactResetTimeString(from: metricData.resetTime)
        case .currency:
            // Show currency amount
            return usage.formattedExtraUsed ?? "$0.00"
        case .both:
            // Show both currency and reset time
            let currency = usage.formattedExtraUsed ?? "$0.00"
            return currency  // Simplified for small widget (limited space)
        }
    }

    // MARK: - No Data View

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: WidgetDesign.NoData.iconSmall))
                .foregroundColor(secondaryTextColor)

            Text("No Data")
                .font(.system(size: WidgetDesign.NoData.titleSmall, weight: .medium))
                .foregroundColor(secondaryTextColor)

            Text("Open app to sync")
                .font(.system(size: WidgetDesign.NoData.subtitleSmall))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(WidgetDesign.Spacing.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Style-dependent colors

    private var ringBackgroundColor: Color {
        Color.white.opacity(0.15)  // Very subtle background for ring track
    }

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private func statusColor(for percentage: Double) -> Color {
        return WidgetDataProvider.shared.colorForUsage(
            percentage,
            mode: entry.colorMode,
            customColorHex: entry.customColorHex
        )
    }
}
