//
//  RequestLogsView.swift
//  Claude Usage - Per-Request API Logs
//
//  Shows per-request API logs from OTel telemetry with
//  summary card, filters, and scrollable request list.
//

import SwiftUI

struct RequestLogsView: View {
    @StateObject private var otelManager = OTelManager.shared

    // Filter state
    @State private var selectedModel: String? = nil
    @State private var selectedRange: DateRange = .today
    @State private var availableModels: [String] = []

    // Data
    @State private var requests: [OTelAPIRequest] = []
    @State private var daySummaries: [OTelDaySummary] = []
    @State private var totalCount: Int = 0

    enum DateRange: String, CaseIterable {
        case today = "Today"
        case week = "7 Days"
        case month = "30 Days"
        case all = "All"

        var fromDate: Date? {
            switch self {
            case .today: return Calendar.current.startOfDay(for: Date())
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .all: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Request Logs",
                    subtitle: "Per-request API cost and token usage from Claude Code"
                )

                if !otelManager.isCollecting && requests.isEmpty {
                    emptyState
                } else {
                    summaryCard
                    filterBar
                    requestList
                }
            }
            .padding()
        }
        .onAppear(perform: loadData)
        .onChange(of: selectedModel) { _, _ in loadData() }
        .onChange(of: selectedRange) { _, _ in loadData() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        SettingsSectionCard(title: "No Events", subtitle: "Enable OTel collection to start receiving telemetry") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("To get started:")
                        .font(DesignTokens.Typography.body)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                    BulletPoint("Enable OTel collection in the OTel Settings page")
                    BulletPoint("Set the required environment variables in your shell")
                    BulletPoint("Launch Claude Code and make some requests")
                }
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let todaySummary = daySummaries.first

        return SettingsSectionCard(title: "Summary — \(selectedRange.rawValue)") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                // Top-level stats
                HStack(spacing: DesignTokens.Spacing.section) {
                    statItem(label: "Cost", value: formatCurrency(todaySummary?.totalCostUSD ?? sumCost()))
                    statItem(label: "Requests", value: "\(todaySummary?.totalRequests ?? requests.count)")
                    statItem(label: "Input Tokens", value: formatTokens(todaySummary?.totalInputTokens ?? sumInputTokens()))
                    statItem(label: "Output Tokens", value: formatTokens(todaySummary?.totalOutputTokens ?? sumOutputTokens()))
                }

                // Per-model breakdown
                if let breakdown = todaySummary?.modelBreakdown, !breakdown.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text("By Model")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)

                        ForEach(breakdown) { model in
                            HStack {
                                modelBadge(model.model)
                                Spacer()
                                Text("\(model.requests) req")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                                Text(formatCurrency(model.costUSD))
                                    .font(DesignTokens.Typography.monospacedSmall)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            // Model picker
            Picker("Model", selection: $selectedModel) {
                Text("All Models").tag(nil as String?)
                ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(model as String?)
                }
            }
            .frame(maxWidth: 200)

            // Date range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Spacer()

            Text("\(totalCount) total")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Request List

    private var requestList: some View {
        LazyVStack(spacing: DesignTokens.Spacing.small) {
            ForEach(requests) { request in
                requestCard(request)
            }

            if requests.isEmpty && otelManager.isCollecting {
                Text("No requests match the current filters")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func requestCard(_ request: OTelAPIRequest) -> some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(request.timestamp))
                    .font(DesignTokens.Typography.monospacedSmall)
                Text(formatDate(request.timestamp))
                    .font(DesignTokens.Typography.tiny)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            // Model badge
            modelBadge(request.model)

            // Tokens
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(request.inputTokens) in")
                    .font(DesignTokens.Typography.monospacedSmall)
                Text("\(request.outputTokens) out")
                    .font(DesignTokens.Typography.monospacedSmall)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, alignment: .trailing)

            // Cache info (compact)
            if request.cacheReadTokens > 0 || request.cacheCreationTokens > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    if request.cacheReadTokens > 0 {
                        Text("\(request.cacheReadTokens) cached")
                            .font(DesignTokens.Typography.tiny)
                            .foregroundColor(.green)
                    }
                    if request.cacheCreationTokens > 0 {
                        Text("\(request.cacheCreationTokens) new cache")
                            .font(DesignTokens.Typography.tiny)
                            .foregroundColor(.orange)
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }

            Spacer()

            // Duration
            Text("\(request.durationMs)ms")
                .font(DesignTokens.Typography.monospacedSmall)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Cost
            Text(formatCurrency(request.costUSD))
                .font(DesignTokens.Typography.monospacedSmall)
                .fontWeight(.medium)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func modelBadge(_ model: String) -> some View {
        let shortName = model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "anthropic.", with: "")

        let color: Color = {
            if model.contains("opus") { return .purple }
            if model.contains("sonnet") { return .blue }
            if model.contains("haiku") { return .green }
            return .gray
        }()

        return Text(shortName)
            .font(DesignTokens.Typography.tiny)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(DesignTokens.Radius.tiny)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DesignTokens.Typography.tiny)
                .foregroundColor(.secondary)
            Text(value)
                .font(DesignTokens.Typography.bodyMedium)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        if value < 0.01 && value > 0 {
            return String(format: "$%.4f", value)
        }
        return String(format: "$%.2f", value)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func sumCost() -> Double {
        requests.reduce(0) { $0 + $1.costUSD }
    }

    private func sumInputTokens() -> Int {
        requests.reduce(0) { $0 + $1.inputTokens }
    }

    private func sumOutputTokens() -> Int {
        requests.reduce(0) { $0 + $1.outputTokens }
    }

    // MARK: - Data Loading

    private func loadData() {
        let db = otelManager.database
        let fromDate = selectedRange.fromDate

        requests = db.fetchAPIRequests(
            limit: 500,
            offset: 0,
            modelFilter: selectedModel,
            fromDate: fromDate
        )

        daySummaries = db.fetchDaySummary(fromDate: fromDate)
        availableModels = db.fetchDistinctModels()
        totalCount = db.totalAPIRequestCount()
    }
}

#Preview {
    RequestLogsView()
        .frame(width: 520, height: 600)
}
