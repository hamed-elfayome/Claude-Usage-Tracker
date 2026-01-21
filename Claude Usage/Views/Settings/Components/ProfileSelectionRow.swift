//
//  ProfileSelectionRow.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-22.
//

import SwiftUI

/// Compact row for selecting profiles in multi-profile display mode
struct ProfileSelectionRow: View {
    let profile: Profile
    let isSelected: Bool
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignTokens.Spacing.small) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                // Profile name (truncated)
                Text(profile.name)
                    .font(DesignTokens.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Active badge
                if isActive {
                    Text("multiprofile.active_badge".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }

                Spacer()

                // Metric indicators (compact badges showing enabled metrics)
                HStack(spacing: 4) {
                    if hasSessionMetric {
                        MetricBadge(letter: "S", color: .blue)
                    }
                    if hasWeekMetric {
                        MetricBadge(letter: "W", color: .purple)
                    }
                    if hasAPIMetric {
                        MetricBadge(letter: "A", color: .orange)
                    }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.extraSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var hasSessionMetric: Bool {
        profile.iconConfig.metrics.first(where: { $0.metricType == .session })?.isEnabled ?? false
    }

    private var hasWeekMetric: Bool {
        profile.iconConfig.metrics.first(where: { $0.metricType == .week })?.isEnabled ?? false
    }

    private var hasAPIMetric: Bool {
        profile.iconConfig.metrics.first(where: { $0.metricType == .api })?.isEnabled ?? false
    }
}

// MARK: - Metric Badge

/// Small badge showing metric type (S, W, A)
private struct MetricBadge: View {
    let letter: String
    let color: Color

    var body: some View {
        Text(letter)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(color.opacity(0.15))
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 8) {
        ProfileSelectionRow(
            profile: Profile(name: "Work Profile"),
            isSelected: true,
            isActive: true,
            onToggle: {}
        )

        ProfileSelectionRow(
            profile: Profile(name: "Personal Account"),
            isSelected: true,
            isActive: false,
            onToggle: {}
        )

        ProfileSelectionRow(
            profile: Profile(name: "Test Environment"),
            isSelected: false,
            isActive: false,
            onToggle: {}
        )
    }
    .padding()
    .frame(width: 400)
}
