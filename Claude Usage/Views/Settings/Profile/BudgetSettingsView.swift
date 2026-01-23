//
//  BudgetSettingsView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import SwiftUI

/// Settings view for configuring monthly budget and alerts
struct BudgetSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared

    @State private var budgetAmount: String = ""
    @State private var alertsEnabled: Bool = false
    @State private var threshold50: Bool = true
    @State private var threshold75: Bool = true
    @State private var threshold90: Bool = true
    @State private var showSaveConfirmation: Bool = false

    private var currentBudget: Double? {
        profileManager.activeProfile?.monthlyBudget
    }

    private var currentSpend: Double {
        profileManager.activeProfile?.claudeCodeMetrics?.totalCost ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("budget.title".localized)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("budget.subtitle".localized)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Current Status Card
                if let budget = currentBudget, budget > 0 {
                    currentStatusCard(budget: budget)
                }

                // Budget Amount Section
                budgetAmountSection

                // Alert Thresholds Section
                alertThresholdsSection

                // Save Button
                HStack {
                    Spacer()

                    Button(action: saveBudgetSettings) {
                        Text("common.save".localized)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(budgetAmount.isEmpty && !alertsEnabled)
                }

                if showSaveConfirmation {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings saved")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Current Status Card

    @ViewBuilder
    private func currentStatusCard(budget: Double) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("budget.current_spend".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(formatCurrency(currentSpend))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("budget.remaining".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(formatCurrency(max(0, budget - currentSpend)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(currentSpend > budget ? .red : .green)
                }
            }

            BudgetProgressBar(
                currentSpend: currentSpend,
                budget: budget,
                thresholds: getActiveThresholds()
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Budget Amount Section

    private var budgetAmountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("budget.monthly_limit".localized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text("budget.monthly_limit_description".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack {
                Text("$")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("750", text: $budgetAmount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onChange(of: budgetAmount) { _, newValue in
                        // Filter to only allow numbers and decimal point
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        if filtered != newValue {
                            budgetAmount = filtered
                        }
                    }

                Text("/ month")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Alert Thresholds Section

    private var alertThresholdsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $alertsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("budget.alerts".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("budget.alerts_description".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            if alertsEnabled {
                VStack(spacing: 8) {
                    thresholdToggle(
                        title: "budget.threshold_50".localized,
                        isOn: $threshold50,
                        color: .yellow
                    )

                    thresholdToggle(
                        title: "budget.threshold_75".localized,
                        isOn: $threshold75,
                        color: .orange
                    )

                    thresholdToggle(
                        title: "budget.threshold_90".localized,
                        isOn: $threshold90,
                        color: .red
                    )
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: alertsEnabled)
    }

    @ViewBuilder
    private func thresholdToggle(title: String, isOn: Binding<Bool>, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Methods

    private func loadCurrentSettings() {
        guard let profile = profileManager.activeProfile else { return }

        if let budget = profile.monthlyBudget {
            budgetAmount = String(format: "%.0f", budget)
        }

        alertsEnabled = profile.budgetAlertsEnabled
        let thresholds = profile.budgetAlertThresholds

        threshold50 = thresholds.contains(50)
        threshold75 = thresholds.contains(75)
        threshold90 = thresholds.contains(90)
    }

    private func saveBudgetSettings() {
        guard let profileId = profileManager.activeProfile?.id else { return }

        // Save budget amount
        if let amount = Double(budgetAmount), amount > 0 {
            profileManager.updateMonthlyBudget(amount, for: profileId)
        } else {
            profileManager.updateMonthlyBudget(nil, for: profileId)
        }

        // Save alert settings
        profileManager.updateBudgetAlertsEnabled(alertsEnabled, for: profileId)
        profileManager.updateBudgetAlertThresholds(getActiveThresholds(), for: profileId)

        // Show confirmation
        withAnimation {
            showSaveConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSaveConfirmation = false
            }
        }
    }

    private func getActiveThresholds() -> [Double] {
        var thresholds: [Double] = []
        if threshold50 { thresholds.append(50) }
        if threshold75 { thresholds.append(75) }
        if threshold90 { thresholds.append(90) }
        return thresholds
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

// MARK: - Preview

#Preview {
    BudgetSettingsView()
        .frame(width: 500, height: 600)
}
