//
//  PaceStatus.swift
//  Claude Usage
//
//  6-tier pace urgency spectrum for pace line coloring.
//  Separate from UsageStatusLevel (3-tier) which controls bar fill color.
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Pace-specific status for the 6-tier color spectrum.
/// Projects end-of-period usage from current consumption rate to determine urgency.
enum PaceStatus: Int, Comparable, CaseIterable {
    case comfortable = 0  // projected <50%  — way under budget
    case onTrack     = 1  // projected 50-75% — sustainable pace
    case warming     = 2  // projected 75-90% — starting to push it
    case pressing    = 3  // projected 90-100% — will likely hit limit
    case critical    = 4  // projected 100-120% — on track to exceed
    case runaway     = 5  // projected >120% — burning way too fast

    static func < (lhs: PaceStatus, rhs: PaceStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Calculate pace status from current usage and elapsed time.
    /// Returns nil when insufficient data (< 3% elapsed or period over).
    static func calculate(usedPercentage: Double, elapsedFraction: Double) -> PaceStatus? {
        guard elapsedFraction >= 0.03, elapsedFraction < 1.0 else {
            return nil
        }
        guard usedPercentage > 0 else { return .comfortable }
        let projected = (usedPercentage / 100.0) / elapsedFraction
        switch projected {
        case ..<0.50:     return .comfortable
        case 0.50..<0.75: return .onTrack
        case 0.75..<0.90: return .warming
        case 0.90..<1.00: return .pressing
        case 1.00..<1.20: return .critical
        default:          return .runaway
        }
    }

    /// SwiftUI color for widgets and SwiftUI views
    var swiftUIColor: Color {
        switch self {
        case .comfortable: return .green
        case .onTrack:     return .teal
        case .warming:     return .yellow
        case .pressing:    return .orange
        case .critical:    return .red
        case .runaway:     return .purple
        }
    }

    #if canImport(AppKit)
    /// AppKit color for menu bar rendering
    var color: NSColor {
        switch self {
        case .comfortable: return NSColor.systemGreen
        case .onTrack:     return NSColor.systemTeal
        case .warming:     return NSColor.systemYellow
        case .pressing:    return NSColor.systemOrange
        case .critical:    return NSColor.systemRed
        case .runaway:     return NSColor.systemPurple
        }
    }
    #endif
}
