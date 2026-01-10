//
//  ThresholdIndicator.swift
//  Claude Usage - Notification Threshold Indicator Component
//

import SwiftUI

/// Displays a threshold indicator for notifications
struct ThresholdIndicator: View {
    let level: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(level)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 32, alignment: .leading)

            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
