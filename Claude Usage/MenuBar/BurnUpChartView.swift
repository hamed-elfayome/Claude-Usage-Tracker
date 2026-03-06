import SwiftUI
import Charts

/// Burn-up chart showing usage progression over a time window.
/// Displayed on the back face of flipped SmartUsageCard instances.
struct BurnUpChartView: View {
    let snapshots: [UsageSnapshot]
    let isPrimary: Bool
    let windowStart: Date
    let windowEnd: Date
    let statusColor: Color

    /// Downsample to at most this many points for rendering performance
    private static let maxPoints = 200

    /// Chart data with a synthetic origin at windowStart so even a single
    /// real data point produces a visible area fill.
    private var displaySnapshots: [UsageSnapshot] {
        let origin = UsageSnapshot(date: windowStart, percentage: 0.0)
        var points = [origin] + snapshots

        // Downsample if needed (skip origin when counting)
        if points.count > Self.maxPoints {
            let stride = max(points.count / Self.maxPoints, 1)
            points = Swift.stride(from: 0, to: points.count, by: stride).map { points[$0] }
        }
        return points
    }

    /// Whether this chart covers a weekly (multi-day) window vs a session window
    private var isWeeklyWindow: Bool {
        windowEnd.timeIntervalSince(windowStart) > Constants.sessionWindow * 2
    }

    private var chartHeight: CGFloat {
        isPrimary ? 80 : 50
    }

    var body: some View {
        if snapshots.isEmpty {
            emptyState
        } else {
            chart
        }
    }

    // MARK: - Chart

    private var startLabel: String {
        if isWeeklyWindow {
            return windowStart.formatted(.dateTime.month(.abbreviated).day())
        }
        return windowStart.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    private var endLabel: String {
        if isWeeklyWindow {
            return windowEnd.formatted(.dateTime.month(.abbreviated).day())
        }
        return windowEnd.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    private var chart: some View {
        VStack(spacing: 2) {
            chartContent
            // Start / End labels below chart
            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.system(size: isPrimary ? 7 : 6))
            .foregroundStyle(.secondary)
        }
    }

    /// Pinned once per render to avoid Date() re-evaluation inside the chart body
    private var now: Date { Date() }

    private var chartContent: some View {
        Chart {
            // Burn-up area + line
            ForEach(displaySnapshots) { snapshot in
                let yValue = snapshot.percentage

                AreaMark(
                    x: .value("Time", snapshot.date),
                    y: .value("Usage", yValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [statusColor.opacity(0.4), statusColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", snapshot.date),
                    y: .value("Usage", yValue)
                )
                .foregroundStyle(statusColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }

            // Pace line: even consumption from 0% to 100%
            let paceStart: Double = 0.0
            let paceEnd: Double = 100.0

            LineMark(
                x: .value("Time", windowStart),
                y: .value("Pace", paceStart),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color(nsColor: .labelColor).opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            LineMark(
                x: .value("Time", windowEnd),
                y: .value("Pace", paceEnd),
                series: .value("Series", "pace")
            )
            .foregroundStyle(Color(nsColor: .labelColor).opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // "Now" marker
            RuleMark(x: .value("Now", now))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
        .chartXScale(domain: windowStart ... windowEnd)
        .chartYScale(domain: 0 ... 100)
        .chartXAxis {
            if isPrimary {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                }
            } else if isWeeklyWindow {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                }
            }
        }
        .chartYAxis {
            if isPrimary {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: chartHeight)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: isPrimary ? 20 : 14))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Collecting data...")
                .font(.system(size: isPrimary ? 10 : 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
    }
}
