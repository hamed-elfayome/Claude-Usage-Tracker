import Foundation

/// Centralized utility for calculating usage status levels with configurable display modes
final class UsageStatusCalculator {

    /// Calculate status level based on percentage and display mode
    /// - Parameters:
    ///   - usedPercentage: The percentage used (0-100)
    ///   - showRemaining: If true, use remaining-based thresholds; if false, use used-based thresholds
    /// - Returns: The appropriate status level
    static func calculateStatus(
        usedPercentage: Double,
        showRemaining: Bool
    ) -> UsageStatusLevel {
        if showRemaining {
            // Old behavior: Based on remaining percentage (like Mac battery)
            // > 20% remaining: safe (green)
            // 10-20% remaining: moderate (orange)
            // < 10% remaining: critical (red)
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
            // New default behavior: Based on used percentage
            // 0-50% used: safe (green)
            // 50-80% used: moderate (orange)
            // 80-100% used: critical (red)
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
