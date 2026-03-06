import Foundation

/// Centralized utility for calculating usage status levels with configurable display modes
final class UsageStatusCalculator {

    /// Calculate status level based on percentage, display mode, and optional session pacing.
    /// - Parameters:
    ///   - usedPercentage: The percentage used (0-100)
    ///   - showRemaining: If true, use remaining-based fallback thresholds; if false, use used-based fallback
    ///   - elapsedFraction: Fraction of the session that has elapsed (0-1). When provided and ≥ 0.15,
    ///     pacing logic fires: status is derived from the projected end-of-session usage
    ///     (`usedFraction / elapsedFraction`), independent of display mode.
    ///     Pass `nil` (default) to fall back to absolute thresholds.
    /// - Returns: The appropriate status level
    static func calculateStatus(
        usedPercentage: Double,
        showRemaining: Bool,
        elapsedFraction: Double? = nil
    ) -> UsageStatusLevel {
        let u = usedPercentage / 100.0

        // Pacing mode: only when enough of the session has elapsed and usage is non-zero.
        // Projected = fraction we'll have consumed by the end of the session at the current rate.
        // Thresholds: green < 0.75, orange 0.75–0.95, red ≥ 0.95
        if let t = elapsedFraction, t >= 0.15, t < 1.0, u > 0 {
            let projected = u / t
            switch projected {
            case ..<0.75:     return .safe
            case 0.75..<0.95: return .moderate
            default:          return .critical
            }
        }

        // Fallback: absolute thresholds (no timing data, or session too early/complete)
        if showRemaining {
            // Based on remaining percentage (like Mac battery)
            // > 20% remaining: safe (green)
            // 10-20% remaining: moderate (orange)
            // < 10% remaining: critical (red)
            let remainingPercentage = max(0, 100 - usedPercentage)
            switch remainingPercentage {
            case 20...:   return .safe
            case 10..<20: return .moderate
            default:      return .critical
            }
        } else {
            // Based on used percentage
            // 0-50% used: safe (green)
            // 50-80% used: moderate (orange)
            // 80-100% used: critical (red)
            switch usedPercentage {
            case 0..<50: return .safe
            case 50..<80: return .moderate
            default:     return .critical
            }
        }
    }

    /// Fraction (0...1) of elapsed time within a period, adjusted for display mode.
    /// Returns nil when the reset time or duration is unavailable.
    /// When the reset time is in the past (period fully elapsed), returns 1.0 (or 0.0 in remaining mode).
    static func elapsedFraction(
        resetTime: Date?,
        duration: TimeInterval,
        showRemaining: Bool
    ) -> Double? {
        guard let reset = resetTime, duration > 0 else { return nil }
        guard reset > Date() else { return showRemaining ? 0.0 : 1.0 }
        let remaining = reset.timeIntervalSince(Date())
        let elapsed = duration - remaining
        let fraction = min(max(elapsed / duration, 0), 1)
        return showRemaining ? 1.0 - fraction : fraction
    }

    /// Get the display percentage based on mode
    /// - Parameters:
    ///   - usedPercentage: The percentage used (0-100)
    ///   - showRemaining: If true, return remaining percentage; if false, return used percentage
    /// - Returns: The percentage to display
    static func getDisplayPercentage(
        usedPercentage: Double,
        showRemaining: Bool
    ) -> Double {
        if showRemaining {
            return max(0, 100 - usedPercentage)
        } else {
            return usedPercentage
        }
    }
}
