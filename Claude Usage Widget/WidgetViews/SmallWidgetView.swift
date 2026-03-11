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
                        .stroke(Color.white.opacity(WidgetDesign.Colors.glassProgressBg), lineWidth: WidgetDesign.Ring.lineWidth)

                    Circle()
                        .trim(from: 0, to: min(metricData.percentage / 100, 1.0))
                        .stroke(
                            statusColor(for: metricData.percentage),
                            style: StrokeStyle(lineWidth: WidgetDesign.Ring.lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Pace marker dot on ring circumference
                    if entry.showPaceMarker, let paceData = usage.paceData(for: entry.smallMetric) {
                        let angleRadians = (-Double.pi / 2) + (paceData.elapsed * 2 * Double.pi)
                        let radius = (WidgetDesign.Ring.size - WidgetDesign.Ring.lineWidth) / 2
                        let centerPt = WidgetDesign.Ring.size / 2
                        Circle()
                            .fill(paceData.pace.color)
                            .frame(width: 5, height: 5)
                            .position(
                                x: centerPt + radius * cos(angleRadians),
                                y: centerPt + radius * sin(angleRadians)
                            )
                    }

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

                // Reset time or cost (for extra metric)
                Text(subtitleText(for: entry.smallMetric, metricData: metricData, usage: usage))
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
                status: WidgetStatusLevel.from(percentage: usage.opusPercentage),
                label: "Opus"
            )
        case .sonnet:
            return MetricDisplayData(
                percentage: usage.sonnetPercentage,
                resetTime: usage.weeklyResetTime,
                status: WidgetStatusLevel.from(percentage: usage.sonnetPercentage),
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

    private var secondaryTextColor: Color {
        Color.primary.opacity(WidgetDesign.Colors.glassSecondaryText)
    }

    private func statusColor(for percentage: Double) -> Color {
        let elapsed: Double? = entry.usePaceColoring
            ? entry.usage?.paceData(for: entry.smallMetric)?.elapsed
            : nil
        return WidgetDataProvider.shared.colorForUsage(
            percentage,
            mode: entry.colorMode,
            customColorHex: entry.customColorHex,
            elapsedFraction: elapsed
        )
    }
}
