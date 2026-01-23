//
//  MiniSparklineView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import SwiftUI

/// A lightweight sparkline visualization for daily cost trends
struct MiniSparklineView: View {
    let data: [Double]
    var trendDirection: TrendDirection = .stable
    var lineColor: Color = .accentColor
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: 4) {
            // Sparkline
            if data.count >= 2 {
                GeometryReader { geometry in
                    sparklinePath(in: geometry.size)
                        .stroke(
                            lineColor.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(height: height)
            } else {
                // Not enough data
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: height)
            }

            // Trend indicator
            Image(systemName: trendDirection.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(trendColor)
        }
    }

    private var trendColor: Color {
        switch trendDirection {
        case .up: return .red.opacity(0.8)
        case .down: return .green.opacity(0.8)
        case .stable: return .secondary
        }
    }

    private func sparklinePath(in size: CGSize) -> Path {
        guard data.count >= 2 else { return Path() }

        let minValue = data.min() ?? 0
        let maxValue = data.max() ?? 1
        let range = maxValue - minValue

        // Avoid division by zero
        let effectiveRange = range > 0 ? range : 1

        let stepX = size.width / CGFloat(data.count - 1)
        let padding: CGFloat = 2  // Vertical padding

        var path = Path()

        for (index, value) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let normalizedY = (value - minValue) / effectiveRange
            let y = size.height - padding - (normalizedY * (size.height - padding * 2))

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Sample data showing upward trend
        MiniSparklineView(
            data: [10, 15, 12, 18, 22, 25, 30],
            trendDirection: .up,
            lineColor: .accentColor
        )
        .frame(width: 80)

        // Sample data showing downward trend
        MiniSparklineView(
            data: [30, 28, 25, 20, 18, 15, 12],
            trendDirection: .down,
            lineColor: .green
        )
        .frame(width: 80)

        // Stable trend
        MiniSparklineView(
            data: [20, 22, 19, 21, 20, 21, 20],
            trendDirection: .stable,
            lineColor: .blue
        )
        .frame(width: 80)
    }
    .padding()
}
