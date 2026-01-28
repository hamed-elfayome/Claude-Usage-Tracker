//
//  UsageHistoryView.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-01-26.
//

import SwiftUI

/// Chart type selector for history view
enum HistoryChartType: String, CaseIterable {
    case sessionResets = "session"
    case weeklyResets = "weekly"
    case billingCycles = "billing"

    var localizedName: String {
        switch self {
        case .sessionResets:
            return "history.tab.session".localized
        case .weeklyResets:
            return "history.tab.weekly".localized
        case .billingCycles:
            return "history.tab.billing".localized
        }
    }

    var icon: String {
        switch self {
        case .sessionResets:
            return "clock.arrow.circlepath"
        case .weeklyResets:
            return "calendar.badge.clock"
        case .billingCycles:
            return "creditcard"
        }
    }

    var resetType: ResetType {
        switch self {
        case .sessionResets:
            return .sessionReset
        case .weeklyResets:
            return .weeklyReset
        case .billingCycles:
            return .billingCycle
        }
    }
}

/// Usage history view showing charts and historical data
struct UsageHistoryView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var selectedChartType: HistoryChartType = .sessionResets
    @State private var historyData: UsageHistoryData = UsageHistoryData()
    @State private var selectedDateRange: DateRangePreset = .last7Days
    @State private var chartStyle: ChartStyle = .line

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Page Header
                SettingsPageHeader(
                    title: "history.title".localized,
                    subtitle: "history.subtitle".localized
                )

                if let _ = profileManager.activeProfile {
                    // Chart Type Picker
                    Picker("", selection: $selectedChartType) {
                        ForEach(HistoryChartType.allCases, id: \.self) { type in
                            Text(type.localizedName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Chart Controls (Date Range + Style)
                    HStack(spacing: 12) {
                        Picker("", selection: $selectedDateRange) {
                            Text("24h").tag(DateRangePreset.today)
                            Text("7d").tag(DateRangePreset.last7Days)
                            Text("30d").tag(DateRangePreset.last30Days)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Spacer()

                        Picker("", selection: $chartStyle) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .tag(ChartStyle.line)
                            Image(systemName: "chart.bar.fill")
                                .tag(ChartStyle.bar)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Chart Section
                    chartSection

                    // History List Section
                    historyListSection

                    // Action Buttons
                    actionButtons
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

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        let filteredSnapshots = currentSnapshots

        switch selectedChartType {
        case .sessionResets:
            SessionUsageChart(snapshots: filteredSnapshots, chartStyle: chartStyle)
        case .weeklyResets:
            WeeklyUsageChart(snapshots: filteredSnapshots, chartStyle: chartStyle)
        case .billingCycles:
            BillingCycleChart(snapshots: filteredSnapshots, chartStyle: chartStyle)
        }
    }

    // MARK: - History List Section

    @ViewBuilder
    private var historyListSection: some View {
        let snapshots = currentSnapshots

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("history.list.title".localized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "history.list.count".localized, snapshots.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if snapshots.isEmpty {
                emptyListView
            } else {
                // Scrollable list with fixed height
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(snapshots.prefix(50).enumerated()), id: \.element.id) { index, snapshot in
                            SnapshotRow(snapshot: snapshot)

                            if index < min(snapshots.count - 1, 49) {
                                Divider()
                            }
                        }

                        if snapshots.count > 50 {
                            HStack {
                                Text(String(format: "history.list.more".localized, snapshots.count - 50))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 200)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    private var currentSnapshots: [UsageSnapshot] {
        let baseSnapshots: [UsageSnapshot]
        switch selectedChartType {
        case .sessionResets:
            baseSnapshots = historyData.sessionSnapshots
        case .weeklyResets:
            baseSnapshots = historyData.weeklySnapshots
        case .billingCycles:
            baseSnapshots = historyData.billingCycleSnapshots
        }

        // Apply date range filter
        let dateRange = DateRangeSelection(preset: selectedDateRange)
        return dateRange.snapshots(from: UsageHistoryData(snapshots: baseSnapshots))
    }

    @ViewBuilder
    private var emptyListView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))

            Text("history.list.empty".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Export Button with format options
            Menu {
                Button("Export as JSON") {
                    exportHistory(format: .json)
                }
                Button("Export as CSV") {
                    exportHistory(format: .csv)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("history.export_button".localized)
                        .font(.system(size: 12))
                }
            }
            .menuStyle(.borderlessButton)
            .frame(height: 28)

            Spacer()

            // Clear Button
            if !currentSnapshots.isEmpty {
                Button(action: clearCurrentHistory) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("history.clear_button".localized)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
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

    // MARK: - Actions

    private func loadHistory() {
        guard let profileId = profileManager.activeProfile?.id else {
            historyData = UsageHistoryData()
            return
        }

        // No need for Task wrapper since we're already on MainActor in SwiftUI views
        historyData = UsageHistoryService.shared.loadHistory(for: profileId)
    }

    private func clearCurrentHistory() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        Task { @MainActor in
            UsageHistoryService.shared.clearHistory(for: profileId, resetType: selectedChartType.resetType)
            loadHistory()
        }
    }

    private func exportHistory(format: UsageHistoryService.ExportFormat = .json) {
        guard let profileId = profileManager.activeProfile?.id else { return }

        UsageHistoryService.shared.exportToFile(
            for: profileId,
            resetType: selectedChartType.resetType,
            format: format
        )
    }
}

// MARK: - Previews

#Preview("History View") {
    UsageHistoryView()
        .frame(width: 520, height: 700)
}
