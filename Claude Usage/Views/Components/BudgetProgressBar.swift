//
//  BudgetProgressBar.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import SwiftUI

/// A progress bar showing budget usage with threshold markers
struct BudgetProgressBar: View {
    let currentSpend: Double
    let budget: Double
    var thresholds: [Double] = [50, 75, 90]  // Percentage thresholds
    var height: CGFloat = 8

    private var percentage: Double {
        guard budget > 0 else { return 0 }
        return min((currentSpend / budget) * 100, 100)
    }

    private var progressColor: Color {
        if percentage >= 90 { return .red }
        if percentage >= 75 { return .orange }
        if percentage >= 50 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 4) {
            // Progress bar with markers
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.secondary.opacity(0.15))

                    // Progress fill
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(
                            LinearGradient(
                                colors: [progressColor, progressColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(percentage / 100, 1.0))
                        .animation(.easeInOut(duration: 0.5), value: percentage)

                    // Threshold markers
                    ForEach(thresholds, id: \.self) { threshold in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 1, height: height)
                            .offset(x: geometry.size.width * (threshold / 100) - 0.5)
                    }
                }
            }
            .frame(height: height)

            // Labels
            HStack {
                Text(formatCurrency(currentSpend))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text(formatCurrency(budget))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}

/// Compact version of budget progress bar for inline display
struct CompactBudgetProgressBar: View {
    let currentSpend: Double
    let budget: Double
    var height: CGFloat = 6

    private var percentage: Double {
        guard budget > 0 else { return 0 }
        return min((currentSpend / budget) * 100, 100)
    }

    private var progressColor: Color {
        if percentage >= 90 { return .red }
        if percentage >= 75 { return .orange }
        if percentage >= 50 { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(height: height)

            // Budget label
            Text(formatBudget(budget))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private func formatBudget(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.0fK", amount / 1000)
        }
        return String(format: "$%.0f", amount)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BudgetProgressBar(
            currentSpend: 534.58,
            budget: 750.0
        )
        .frame(width: 200)

        BudgetProgressBar(
            currentSpend: 680,
            budget: 750.0
        )
        .frame(width: 200)

        BudgetProgressBar(
            currentSpend: 720,
            budget: 750.0
        )
        .frame(width: 200)

        CompactBudgetProgressBar(
            currentSpend: 534.58,
            budget: 750.0
        )
        .frame(width: 150)
    }
    .padding()
}
