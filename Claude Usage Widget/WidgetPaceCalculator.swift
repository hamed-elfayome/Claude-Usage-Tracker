//
//  WidgetPaceCalculator.swift
//  Claude Usage Widget
//
//  6-tier pace urgency for widget rendering + elapsed fraction computation.
//  Self-contained copy because PBXFileSystemSynchronizedRootGroup prevents
//  cross-target file sharing with main app's PaceStatus.swift.
//

import SwiftUI

/// 6-tier pace urgency spectrum (mirrors main app's PaceStatus enum).
enum WidgetPaceStatus: Int, Comparable, CaseIterable {
    case comfortable = 0  // projected <75%   — plenty of headroom
    case onTrack     = 1  // projected 75-100% — using allocation well
    case warming     = 2  // projected 100-110% — might hit the limit
    case pressing    = 3  // projected 110-120% — will likely run short
    case critical    = 4  // projected 120-135% — running out early
    case runaway     = 5  // projected >135%  — burning way too fast

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Calculate pace status from current usage and elapsed time.
    /// Returns nil when insufficient data (< 3% elapsed or period over).
    static func calculate(usedPercentage: Double, elapsedFraction: Double) -> WidgetPaceStatus? {
        guard elapsedFraction >= 0.03, elapsedFraction < 1.0 else { return nil }
        guard usedPercentage > 0 else { return .comfortable }
        let projected = (usedPercentage / 100.0) / elapsedFraction
        switch projected {
        case ..<0.75:     return .comfortable
        case 0.75..<1.00: return .onTrack
        case 1.00..<1.10: return .warming
        case 1.10..<1.20: return .pressing
        case 1.20..<1.35: return .critical
        default:          return .runaway
        }
    }

    var color: Color {
        switch self {
        case .comfortable: return .green
        case .onTrack:     return .teal
        case .warming:     return .yellow
        case .pressing:    return .orange
        case .critical:    return .red
        case .runaway:     return .purple
        }
    }
}

/// Computes elapsed fractions and pace status for widget views.
enum WidgetPaceCalculator {
    /// 5-hour session window (matches Constants.sessionWindow in main app)
    static let sessionDuration: TimeInterval = 5 * 60 * 60
    /// 7-day weekly window (matches Constants.weeklyWindow in main app)
    static let weeklyDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Computes elapsed fraction (0...1) from reset time and total duration.
    /// Returns nil if inputs are invalid. Returns 1.0 if period is over.
    static func elapsedFraction(resetTime: Date?, duration: TimeInterval) -> Double? {
        guard let reset = resetTime, duration > 0 else { return nil }
        guard reset > Date() else { return 1.0 }
        let remaining = reset.timeIntervalSince(Date())
        let elapsed = duration - remaining
        return min(max(elapsed / duration, 0), 1)
    }
}

// MARK: - WidgetUsageData Pace Extensions

extension WidgetUsageData {
    /// Elapsed fraction of the current 5-hour session window (0...1)
    var sessionElapsedFraction: Double? {
        WidgetPaceCalculator.elapsedFraction(
            resetTime: sessionResetTime,
            duration: WidgetPaceCalculator.sessionDuration
        )
    }

    /// Elapsed fraction of the current 7-day weekly window (0...1)
    var weeklyElapsedFraction: Double? {
        WidgetPaceCalculator.elapsedFraction(
            resetTime: weeklyResetTime,
            duration: WidgetPaceCalculator.weeklyDuration
        )
    }

    /// Returns (elapsedFraction, paceStatus) for any widget metric type.
    /// Routes session metrics to session elapsed, weekly/opus/sonnet to weekly elapsed.
    /// Returns nil for extra (no fixed period) or when pace can't be computed.
    func paceData(for metric: WidgetSmallMetric) -> (elapsed: Double, pace: WidgetPaceStatus)? {
        let elapsed: Double?
        let percentage: Double

        switch metric {
        case .session:
            elapsed = sessionElapsedFraction
            percentage = sessionPercentage
        case .weekly:
            elapsed = weeklyElapsedFraction
            percentage = weeklyPercentage
        case .opus:
            elapsed = weeklyElapsedFraction
            percentage = opusPercentage
        case .sonnet:
            elapsed = weeklyElapsedFraction
            percentage = sonnetPercentage
        case .extra:
            return nil
        }

        guard let e = elapsed,
              let pace = WidgetPaceStatus.calculate(usedPercentage: percentage, elapsedFraction: e)
        else { return nil }
        return (e, pace)
    }
}
