import SwiftUI

struct LimitOptimizationGuideView: View {
    @State private var selectedCategory: TipCategory = .claudeAI
    @State private var copiedCommand: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "guide.title".localized,
                    subtitle: "Limit Optimization Guide"
                )

                // Category picker
                HStack(spacing: DesignTokens.Spacing.small) {
                    ForEach(TipCategory.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.displayName)
                                .font(DesignTokens.Typography.body)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .fill(selectedCategory == category ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                        .strokeBorder(selectedCategory == category ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Tips list
                let tips = LimitOptimizationTipService.shared.tipsForCategory(selectedCategory)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    ForEach(tips) { tip in
                        TipCard(
                            tip: tip,
                            copiedCommand: $copiedCommand
                        )
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}

struct TipCard: View {
    let tip: LimitOptimizationTip
    @Binding var copiedCommand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.titleKey.localized)
                        .font(DesignTokens.Typography.bodyMedium)
                        .fontWeight(.medium)

                    Text(tip.detailKey.localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let actionData = tip.actionData, actionData.type != .none {
                    Button {
                        if actionData.type == .copy, let value = actionData.value {
                            copyToClipboard(value)
                            copiedCommand = value
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if copiedCommand == value {
                                    copiedCommand = nil
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedCommand == tip.actionData?.value ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(copiedCommand == tip.actionData?.value ? "guide.copied".localized : "guide.copy_command".localized)
                                .font(DesignTokens.Typography.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 6) {
                Text(tip.actionStyle.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )

                Text(tip.riskLevel.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(tip.riskLevel.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(tip.riskLevel.color.opacity(0.1))
                    )
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.cardBackground)
        )
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension TipCategory {
    var displayName: String {
        switch self {
        case .claudeAI:
            return "guide.claude_ai".localized
        case .claudeCode:
            return "guide.claude_code".localized
        case .claudeCowork:
            return "guide.claude_cowork".localized
        }
    }
}

extension TipActionStyle {
    var displayName: String {
        switch self {
        case .actionable:
            return "Actionable"
        case .informational:
            return "Informational"
        case .checklist:
            return "Checklist"
        }
    }
}

extension TipRiskLevel {
    var displayName: String {
        switch self {
        case .safe:
            return "Safe"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    var color: Color {
        switch self {
        case .safe:
            return .adaptiveGreen
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}