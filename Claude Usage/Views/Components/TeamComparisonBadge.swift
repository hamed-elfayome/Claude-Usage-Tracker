//
//  TeamComparisonBadge.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import SwiftUI

/// A compact badge showing comparison to team average
struct TeamComparisonBadge: View {
    let percentageDiff: Double  // Positive = above average, negative = below
    let rank: Int?
    let totalUsers: Int?

    private var isAboveAverage: Bool {
        percentageDiff > 0
    }

    private var backgroundColor: Color {
        if isAboveAverage {
            return .red.opacity(0.12)
        } else {
            return .green.opacity(0.12)
        }
    }

    private var textColor: Color {
        if isAboveAverage {
            return .red
        } else {
            return .green
        }
    }

    private var formattedPercentage: String {
        let sign = percentageDiff >= 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, percentageDiff)
    }

    private var formattedRank: String? {
        guard let rank = rank, let total = totalUsers else { return nil }
        return "#\(rank)/\(total)"
    }

    var body: some View {
        HStack(spacing: 4) {
            // Percentage difference
            Text(formattedPercentage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(textColor)

            // Separator and rank (if available)
            if let rankStr = formattedRank {
                Text(rankStr)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
    }
}

/// Inline version for header display
struct InlineTeamComparisonBadge: View {
    let percentageDiff: Double
    let rank: Int?
    let totalUsers: Int?

    private var isAboveAverage: Bool {
        percentageDiff > 0
    }

    private var textColor: Color {
        if isAboveAverage {
            return .red.opacity(0.8)
        } else {
            return .green.opacity(0.8)
        }
    }

    private var formattedText: String {
        let sign = percentageDiff >= 0 ? "+" : ""
        var text = String(format: "%@%.0f%% vs team", sign, percentageDiff)

        if let rank = rank, let total = totalUsers {
            text += " #\(rank)/\(total)"
        }

        return text
    }

    var body: some View {
        Text(formattedText)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(textColor)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Above average
        TeamComparisonBadge(
            percentageDiff: 15,
            rank: 2,
            totalUsers: 36
        )

        // Below average
        TeamComparisonBadge(
            percentageDiff: -20,
            rank: 28,
            totalUsers: 36
        )

        // No rank
        TeamComparisonBadge(
            percentageDiff: 5,
            rank: nil,
            totalUsers: nil
        )

        // Inline versions
        InlineTeamComparisonBadge(
            percentageDiff: 15,
            rank: 2,
            totalUsers: 36
        )

        InlineTeamComparisonBadge(
            percentageDiff: -20,
            rank: 28,
            totalUsers: 36
        )
    }
    .padding()
}
