import SwiftUI

/// Section showing OpenAI API billing in the popover
struct OpenAIBillingSection: View {
    let profile: Profile

    var body: some View {
        if let usage = profile.openaiUsage {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("Resets \(usage.resetsAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("This month")
                    Spacer()
                    Text(usage.formattedUsed)
                        .foregroundStyle(.blue)
                }
                .font(.caption)

                if let budget = profile.spendBudgetCents, budget > 0 {
                    let remaining = Double(budget - usage.currentSpendCents) / 100.0
                    HStack {
                        Text("Budget remaining")
                        Spacer()
                        Text("$\(String(format: "%.2f", remaining))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Section showing Codex rate limits in the popover
struct CodexSection: View {
    let profile: Profile

    var body: some View {
        if let usage = profile.codexUsage {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("Resets \(usage.requestResetTime, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Requests")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Spacer()
                        Text("\(String(format: "%.0f", usage.requestPercentageUsed))%")
                            .font(.caption2)
                    }
                    ProgressView(value: usage.requestPercentageUsed, total: 100)
                        .tint(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.0f", usage.tokenPercentageUsed))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: usage.tokenPercentageUsed, total: 100)
                        .tint(.secondary)
                }

                Text("OpenAI API Rate Limits")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
