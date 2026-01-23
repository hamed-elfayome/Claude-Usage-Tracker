//
//  ModelBreakdownView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import SwiftUI

/// A horizontal stacked bar showing model usage breakdown
struct ModelBreakdownView: View {
    let opusPercentage: Double
    let sonnetPercentage: Double
    let haikuPercentage: Double
    var showLegend: Bool = true
    var height: CGFloat = 8

    // Optional: actual costs for legend
    var opusCost: Double?
    var sonnetCost: Double?
    var haikuCost: Double?

    private var opusColor: Color { .purple }
    private var sonnetColor: Color { .blue }
    private var haikuColor: Color { .green }

    var body: some View {
        VStack(spacing: 6) {
            // Stacked bar
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Opus segment
                    if opusPercentage > 0 {
                        RoundedRectangle(cornerRadius: opusPercentage == 100 ? height / 2 : 0)
                            .fill(opusColor)
                            .frame(width: geometry.size.width * (opusPercentage / 100))
                            .cornerRadius(height / 2, corners: [.topLeft, .bottomLeft])
                    }

                    // Sonnet segment
                    if sonnetPercentage > 0 {
                        Rectangle()
                            .fill(sonnetColor)
                            .frame(width: geometry.size.width * (sonnetPercentage / 100))
                    }

                    // Haiku segment
                    if haikuPercentage > 0 {
                        RoundedRectangle(cornerRadius: haikuPercentage == 100 ? height / 2 : 0)
                            .fill(haikuColor)
                            .frame(width: geometry.size.width * (haikuPercentage / 100))
                            .cornerRadius(height / 2, corners: [.topRight, .bottomRight])
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.secondary.opacity(0.1))
                )
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            }
            .frame(height: height)

            // Legend
            if showLegend {
                HStack(spacing: 12) {
                    if opusPercentage > 0 {
                        ModelLegendItem(
                            color: opusColor,
                            name: "Opus",
                            percentage: opusPercentage,
                            cost: opusCost
                        )
                    }

                    if sonnetPercentage > 0 {
                        ModelLegendItem(
                            color: sonnetColor,
                            name: "Sonnet",
                            percentage: sonnetPercentage,
                            cost: sonnetCost
                        )
                    }

                    if haikuPercentage > 0 {
                        ModelLegendItem(
                            color: haikuColor,
                            name: "Haiku",
                            percentage: haikuPercentage,
                            cost: haikuCost
                        )
                    }
                }
            }
        }
    }
}

/// A single legend item for model breakdown
struct ModelLegendItem: View {
    let color: Color
    let name: String
    let percentage: Double
    var cost: Double?

    var body: some View {
        HStack(spacing: 4) {
            // Color indicator
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            // Name and percentage
            Text("\(name) \(Int(percentage))%")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            // Cost (if available)
            if let cost = cost {
                Text(formatCost(cost))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }

    private func formatCost(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.1fK", amount / 1000)
        }
        return String(format: "$%.0f", amount)
    }
}

/// Compact inline model breakdown (no legend)
struct CompactModelBreakdownView: View {
    let opusPercentage: Double
    let sonnetPercentage: Double
    let haikuPercentage: Double
    var height: CGFloat = 6

    var body: some View {
        ModelBreakdownView(
            opusPercentage: opusPercentage,
            sonnetPercentage: sonnetPercentage,
            haikuPercentage: haikuPercentage,
            showLegend: false,
            height: height
        )
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - UIRectCorner for macOS

struct UIRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// MARK: - NSBezierPath Extension

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()

        let radius = cornerRadii.width

        let topLeft = corners.contains(.topLeft) ? radius : 0
        let topRight = corners.contains(.topRight) ? radius : 0
        let bottomLeft = corners.contains(.bottomLeft) ? radius : 0
        let bottomRight = corners.contains(.bottomRight) ? radius : 0

        // Start from top-left
        move(to: NSPoint(x: rect.minX + topLeft, y: rect.minY))

        // Top edge and top-right corner
        line(to: NSPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            appendArc(from: NSPoint(x: rect.maxX, y: rect.minY),
                     to: NSPoint(x: rect.maxX, y: rect.minY + topRight),
                     radius: topRight)
        }

        // Right edge and bottom-right corner
        line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY),
                     to: NSPoint(x: rect.maxX - bottomRight, y: rect.maxY),
                     radius: bottomRight)
        }

        // Bottom edge and bottom-left corner
        line(to: NSPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            appendArc(from: NSPoint(x: rect.minX, y: rect.maxY),
                     to: NSPoint(x: rect.minX, y: rect.maxY - bottomLeft),
                     radius: bottomLeft)
        }

        // Left edge and top-left corner
        line(to: NSPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            appendArc(from: NSPoint(x: rect.minX, y: rect.minY),
                     to: NSPoint(x: rect.minX + topLeft, y: rect.minY),
                     radius: topLeft)
        }

        close()
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }

        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Full breakdown with legend
        ModelBreakdownView(
            opusPercentage: 60,
            sonnetPercentage: 35,
            haikuPercentage: 5,
            opusCost: 320.75,
            sonnetCost: 187.12,
            haikuCost: 26.71
        )
        .frame(width: 250)

        // Sonnet dominant
        ModelBreakdownView(
            opusPercentage: 10,
            sonnetPercentage: 80,
            haikuPercentage: 10
        )
        .frame(width: 250)

        // Compact version
        CompactModelBreakdownView(
            opusPercentage: 60,
            sonnetPercentage: 35,
            haikuPercentage: 5
        )
        .frame(width: 150)
    }
    .padding()
}
