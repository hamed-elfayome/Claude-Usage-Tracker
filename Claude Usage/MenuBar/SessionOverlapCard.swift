import SwiftUI

struct SessionOverlapCard: View {
    let profile: Profile
    @StateObject private var planningService = SessionPlanningService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                Text("Session Plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            if planningService.isSessionActive(for: profile),
               let usage = profile.claudeUsage {
                let estimatedStart = usage.sessionResetTime.addingTimeInterval(-Constants.sessionWindow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session active since \(FormatterHelper.timeString(from: estimatedStart))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Resets \(FormatterHelper.timeString(from: usage.sessionResetTime))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else if let pingTime = planningService.calculateRecommendedPingTime(for: profile),
                      let plannedWorkStart = profile.sessionPlanningSettings?.plannedWorkStart {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next ping: \(FormatterHelper.timeString(from: pingTime))")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text("Work starts: \(FormatterHelper.timeString(from: plannedWorkStart))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No active plan")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.04))
                )
        )
        .padding(.horizontal, 14)
    }
}