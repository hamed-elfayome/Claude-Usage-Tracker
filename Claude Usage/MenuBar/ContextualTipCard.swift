import SwiftUI

struct ContextualTipCard: View {
    let profile: Profile
    let usage: ClaudeUsage
    @State private var currentTip: LimitOptimizationTip?
    @State private var copiedCommand: String?

    var body: some View {
        if let tip = currentTip,
           shouldShowTip {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)

                    Text("Tip")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()
                }

                HStack(alignment: .top, spacing: 4) {
                    Text(tip.titleKey.localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Spacer()

                    if let actionData = tip.actionData, actionData.type != .none {
                        Button {
                            if actionData.type == .copy, let value = actionData.value {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(value, forType: .string)
                                copiedCommand = value
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedCommand = nil
                                }
                            }
                        } label: {
                            Image(systemName: copiedCommand == tip.actionData?.value ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 14)
            .onAppear {
                loadTip()
            }
        } else {
            EmptyView()
        }
    }

    private var shouldShowTip: Bool {
        guard let settings = profile.sessionPlanningSettings else { return false }
        if usage.effectiveSessionPercentage > 80 {
            return settings.planModeTipsEnabled
        }
        return true
    }

    private func loadTip() {
        let isPeak = PeakHoursService.shared.isPeakHours
        currentTip = LimitOptimizationTipService.shared.rotatingTip(
            sessionPercentage: usage.effectiveSessionPercentage,
            isPeakHours: isPeak,
            lastTipId: nil
        )
    }
}