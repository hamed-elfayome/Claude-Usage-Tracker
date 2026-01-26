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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page Header
                SettingsPageHeader(
                    title: "history.title".localized,
                    subtitle: "history.subtitle".localized
                )

                if let profile = profileManager.activeProfile {
                    // Chart Type Picker
                    Picker("", selection: $selectedChartType) {
                        ForEach(HistoryChartType.allCases, id: \.self) { type in
                            Label(type.localizedName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

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
        .onChange(of: profileManager.activeProfile?.id) { _ in
            loadHistory()
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        switch selectedChartType {
        case .sessionResets:
            SessionUsageChart(snapshots: historyData.sessionSnapshots)
        case .weeklyResets:
            WeeklyUsageChart(snapshots: historyData.weeklySnapshots)
        case .billingCycles:
            BillingCycleChart(snapshots: historyData.billingCycleSnapshots)
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
        switch selectedChartType {
        case .sessionResets:
            return historyData.sessionSnapshots
        case .weeklyResets:
            return historyData.weeklySnapshots
        case .billingCycles:
            return historyData.billingCycleSnapshots
        }
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
            // Export Button
            Button(action: exportHistory) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("history.export_button".localized)
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)

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

        Task { @MainActor in
            historyData = UsageHistoryService.shared.loadHistory(for: profileId)
        }
    }

    private func clearCurrentHistory() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        Task { @MainActor in
            UsageHistoryService.shared.clearHistory(for: profileId, resetType: selectedChartType.resetType)
            loadHistory()
        }
    }

    private func exportHistory() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        Task { @MainActor in
            UsageHistoryService.shared.exportToFile(for: profileId, resetType: selectedChartType.resetType)
        }
    }
}

// MARK: - Previews

#Preview("History View") {
    UsageHistoryView()
        .frame(width: 520, height: 700)
}
