//
//  UsageHistoryView.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-01-26.
//

import SwiftUI
import Charts

/// Time scale options for charts
enum ChartTimeScale: Double, CaseIterable {
    case hours5 = 5
    case hours24 = 24
    case days7 = 168      // 7 * 24
    case days30 = 720     // 30 * 24

    var label: String {
        switch self {
        case .hours5: return "5h"
        case .hours24: return "24h"
        case .days7: return "7d"
        case .days30: return "30d"
        }
    }
}

/// Usage history view showing charts and historical data
struct UsageHistoryView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var historyData: UsageHistoryData = UsageHistoryData()
    @State private var selectedTimeScale: ChartTimeScale = .hours24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page Header with time scale dropdown
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("history.title".localized)
                            .font(.system(size: 20, weight: .semibold))
                        Text("history.subtitle".localized)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Time scale dropdown
                    Picker("", selection: $selectedTimeScale) {
                        Text("history.time_scale.5_hours".localized).tag(ChartTimeScale.hours5)
                        Text("history.time_scale.24_hours".localized).tag(ChartTimeScale.hours24)
                        Text("history.time_scale.7_days".localized).tag(ChartTimeScale.days7)
                        Text("history.time_scale.30_days".localized).tag(ChartTimeScale.days30)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                if let _ = profileManager.activeProfile {
                    // Combined Usage Chart (session + weekly)
                    CombinedUsageChart(
                        sessionSnapshots: historyData.sessionSnapshots,
                        weeklySnapshots: historyData.weeklySnapshots,
                        timeScale: $selectedTimeScale
                    )

                    // Billing Section
                    billingSection

                    // Export Button
                    exportSection

                } else {
                    noProfileView
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadHistory()
        }
        .onChange(of: profileManager.activeProfile?.id) {
            loadHistory()
        }
    }

    // MARK: - Billing Section

    @ViewBuilder
    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("history.chart.api_billing".localized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Chart
            if historyData.billingCycleSnapshots.isEmpty {
                emptyChartView
            } else {
                BillingCycleChart(snapshots: historyData.billingCycleSnapshots, chartStyle: .bar)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyChartView: some View {
        HStack {
            Spacer()
            Text("history.chart.no_data".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 100)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var noProfileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("history.no_profile".localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Export Section

    @ViewBuilder
    private var exportSection: some View {
        HStack {
            Spacer()

            Menu {
                Button(action: { exportHistory(format: .json) }) {
                    Label("history.export.json".localized, systemImage: "doc.text")
                }
                Button(action: { exportHistory(format: .csv) }) {
                    Label("history.export.csv".localized, systemImage: "tablecells")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("history.export.title".localized)
                        .font(.system(size: 12))
                }
                .foregroundColor(.accentColor)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func loadHistory() {
        guard let profileId = profileManager.activeProfile?.id else {
            historyData = UsageHistoryData()
            return
        }

        historyData = UsageHistoryService.shared.loadHistory(for: profileId)
    }

    private func exportHistory(format: UsageHistoryService.ExportFormat) {
        guard let profileId = profileManager.activeProfile?.id else { return }

        UsageHistoryService.shared.exportToFile(
            for: profileId,
            format: format
        )
    }
}

// MARK: - Simple Usage Chart with Scroll

struct SimpleUsageChart: View {
    let title: String
    let snapshots: [UsageSnapshot]
    let valueKeyPath: KeyPath<UsageSnapshot, Double?>
    @Binding var timeScale: ChartTimeScale

    /// Time offset in hours (0 = now, negative = past)
    @State private var timeOffset: Double = 0

    /// Window duration from selected scale
    private var windowHours: Double {
        timeScale.rawValue
    }

    private var visibleRange: (start: Date, end: Date) {
        let now = Date()
        let end = now.addingTimeInterval(timeOffset * 3600)
        let start = end.addingTimeInterval(-windowHours * 3600)
        return (start, end)
    }

    private var visibleSnapshots: [UsageSnapshot] {
        let range = visibleRange
        return snapshots.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
    }

    private var canGoForward: Bool {
        timeOffset < 0
    }

    private var canGoBack: Bool {
        guard let oldest = snapshots.last else { return false }
        let range = visibleRange
        return oldest.timestamp < range.start
    }

    /// Step size for navigation (half the window)
    private var stepHours: Double {
        windowHours / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title row
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Chart
            Chart(visibleSnapshots) { snapshot in
                if let value = snapshot[keyPath: valueKeyPath] {
                    AreaMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("Usage", min(max(value, 0), 100))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.stepEnd)

                    LineMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("Usage", min(max(value, 0), 100))
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(domain: visibleRange.start...visibleRange.end)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat)
                        .font(.system(size: 9))
                }
            }
            .frame(height: 130)
            .padding(12)

            // Bottom bar: navigation
            HStack(spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset -= stepHours } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.3)

                Spacer()

                // Time range label
                Text(timeRangeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset = 0 } }) {
                    Text("history.chart.now".localized)
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(timeOffset == 0)
                .opacity(timeOffset == 0 ? 0.3 : 1)

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset += stepHours } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(8)
        .onChange(of: timeScale) {
            // Reset to now when scale changes
            timeOffset = 0
        }
    }

    private var timeRangeLabel: String {
        let range = visibleRange
        let formatter = DateFormatter()
        switch timeScale {
        case .hours5, .hours24:
            formatter.dateFormat = SharedDataStore.shared.uses24HourTime() ? "MMM d, HH:mm" : "MMM d, h:mma"
        case .days7, .days30:
            formatter.dateFormat = "MMM d"
        }
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
    }

    private var xAxisFormat: Date.FormatStyle {
        switch timeScale {
        case .hours5, .hours24:
            return .dateTime.hour().minute()
        case .days7:
            return .dateTime.weekday(.abbreviated).hour()
        case .days30:
            return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Combined Usage Chart

/// Identifies which data series a chart point belongs to
enum UsageSeries: String, CaseIterable {
    case session
    case weekly

    var color: Color {
        switch self {
        case .session: return .accentColor
        case .weekly: return .indigo
        }
    }

    var lineStyle: StrokeStyle {
        switch self {
        case .session: return StrokeStyle(lineWidth: 2)
        case .weekly: return StrokeStyle(lineWidth: 2, dash: [6, 4])
        }
    }

    var label: String {
        switch self {
        case .session: return "history.chart.session_usage".localized
        case .weekly: return "history.chart.weekly_usage".localized
        }
    }
}

/// A single data point for the combined chart
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let percentage: Double
    let series: UsageSeries
}

/// Combined chart overlaying session and weekly usage on one shared axis
struct CombinedUsageChart: View {
    let sessionSnapshots: [UsageSnapshot]
    let weeklySnapshots: [UsageSnapshot]
    @Binding var timeScale: ChartTimeScale

    @State private var timeOffset: Double = 0

    private var windowHours: Double {
        timeScale.rawValue
    }

    private var visibleRange: (start: Date, end: Date) {
        let now = Date()
        let end = now.addingTimeInterval(timeOffset * 3600)
        let start = end.addingTimeInterval(-windowHours * 3600)
        return (start, end)
    }

    private var chartDataPoints: [ChartDataPoint] {
        let range = visibleRange
        let sessionPoints = sessionSnapshots
            .filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
            .compactMap { snapshot -> ChartDataPoint? in
                guard let value = snapshot.sessionPercentage else { return nil }
                return ChartDataPoint(timestamp: snapshot.timestamp, percentage: min(max(value, 0), 100), series: .session)
            }
        let weeklyPoints = weeklySnapshots
            .filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
            .compactMap { snapshot -> ChartDataPoint? in
                guard let value = snapshot.weeklyPercentage else { return nil }
                return ChartDataPoint(timestamp: snapshot.timestamp, percentage: min(max(value, 0), 100), series: .weekly)
            }
        return sessionPoints + weeklyPoints
    }

    private var hasAnyData: Bool {
        !chartDataPoints.isEmpty
    }

    private var canGoForward: Bool {
        timeOffset < 0
    }

    private var canGoBack: Bool {
        let allSnapshots = sessionSnapshots + weeklySnapshots
        guard let oldest = allSnapshots.map(\.timestamp).min() else { return false }
        return oldest < visibleRange.start
    }

    private var stepHours: Double {
        windowHours / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title row with inline legend
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("history.chart.usage_overview".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Inline legend
                HStack(spacing: 12) {
                    legendItem(series: .session)
                    legendItem(series: .weekly)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if hasAnyData {
                // Chart
                Chart(chartDataPoints) { point in
                    if point.series == .session {
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Usage", point.percentage)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.stepEnd)
                    }

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage", point.percentage),
                        series: .value("Series", point.series.rawValue)
                    )
                    .foregroundStyle(point.series.color)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(point.series.lineStyle)
                }
                .chartXScale(domain: visibleRange.start...visibleRange.end)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisFormat)
                            .font(.system(size: 9))
                    }
                }
                .frame(height: 160)
                .padding(12)
            } else {
                // Empty state
                HStack {
                    Spacer()
                    Text("history.chart.no_data".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 160)
            }

            // Bottom bar: navigation
            HStack(spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset -= stepHours } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.3)

                Spacer()

                Text(timeRangeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset = 0 } }) {
                    Text("history.chart.now".localized)
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(timeOffset == 0)
                .opacity(timeOffset == 0 ? 0.3 : 1)

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { timeOffset += stepHours } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(8)
        .onChange(of: timeScale) {
            timeOffset = 0
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func legendItem(series: UsageSeries) -> some View {
        HStack(spacing: 4) {
            // Line sample
            ZStack {
                if series == .session {
                    Rectangle()
                        .fill(series.color.opacity(0.2))
                        .frame(width: 16, height: 8)
                }
                Rectangle()
                    .fill(series.color)
                    .frame(width: 16, height: series == .weekly ? 1.5 : 2)
                    .overlay {
                        if series == .weekly {
                            // Dashed appearance
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 2, height: 1.5)
                                }
                            }
                        }
                    }
            }

            Text(series.label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private var timeRangeLabel: String {
        let range = visibleRange
        let formatter = DateFormatter()
        switch timeScale {
        case .hours5, .hours24:
            formatter.dateFormat = SharedDataStore.shared.uses24HourTime() ? "MMM d, HH:mm" : "MMM d, h:mma"
        case .days7, .days30:
            formatter.dateFormat = "MMM d"
        }
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
    }

    private var xAxisFormat: Date.FormatStyle {
        switch timeScale {
        case .hours5, .hours24:
            return .dateTime.hour().minute()
        case .days7:
            return .dateTime.weekday(.abbreviated).hour()
        case .days30:
            return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Previews

#Preview("History View") {
    UsageHistoryView()
        .frame(width: 520, height: 700)
}
