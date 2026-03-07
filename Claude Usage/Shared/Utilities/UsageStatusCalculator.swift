import Foundation

/// Centralized utility for calculating usage status levels with configurable display modes
final class UsageStatusCalculator {

    /// Calculate status level based on percentage, display mode, and optional pacing
    /// - Parameters:
    ///   - usedPercentage: The percentage used (0-100)
    ///   - showRemaining: If true, use remaining-based thresholds; if false, use used-based thresholds
    ///   - elapsedFraction: Optional fraction (0-1) of time elapsed in the period; enables pace-aware coloring
    /// - Returns: The appropriate status level
    static func calculateStatus(
        usedPercentage: Double,
        showRemaining: Bool,
        elapsedFraction: Double? = nil
    ) -> UsageStatusLevel {
        // Pace-aware logic: project end-of-period usage when enough time has elapsed
        let u = usedPercentage / 100.0
        if let t = elapsedFraction, t >= 0.15, t < 1.0, u > 0 {
            let projected = u / t
            switch projected {
            case ..<0.75:     return .safe
            case 0.75..<0.95: return .moderate
            default:          return .critical
            }
        }

        if showRemaining {
            let remainingPercentage = max(0, 100 - usedPercentage)
            switch remainingPercentage {
            case 20...:
                return .safe
            case 10..<20:
                return .moderate
            default:
                return .critical
            }
        } else {
            switch usedPercentage {
            case 0..<50:
                return .safe
            case 50..<80:
                return .moderate
            default:
                return .critical
            }
        }
    }

    /// Fraction (0...1) of elapsed time within a period, adjusted for display mode
    /// - Parameters:
    ///   - resetTime: When the period resets
    ///   - duration: Total period duration in seconds
    ///   - showRemaining: If true, returns inverted fraction (1 - elapsed)
    /// - Returns: Elapsed fraction, or nil if inputs are invalid
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
