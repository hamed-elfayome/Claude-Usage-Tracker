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
            case ..<0.70:     return .safe
            case 0.70..<0.90: return .moderate
            default:          return .critical
            }
        }

        if showRemaining {
            let remainingPercentage = max(0, 100 - usedPercentage)
            switch remainingPercentage {
            case 30...:
                return .safe
            case 10..<30:
                return .moderate
            default:
                return .critical
            }
        } else {
            switch usedPercentage {
            case 0..<70:
                return .safe
            case 70..<90:
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
    ///   - excludingWeekends: If true, only weekday time counts, so the fraction holds still over the weekend
    ///   - now: Reference date (defaults to the current date)
    ///   - calendar: Calendar whose time zone and locale define days and weekend days
    /// - Returns: Elapsed fraction, or nil if inputs are invalid
    static func elapsedFraction(
        resetTime: Date?,
        duration: TimeInterval,
        showRemaining: Bool,
        excludingWeekends: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        guard let reset = resetTime, duration > 0 else { return nil }
        guard reset > now else { return showRemaining ? 0.0 : 1.0 }
        let remaining = reset.timeIntervalSince(now)
        let elapsed = duration - remaining
        var fraction = min(max(elapsed / duration, 0), 1)

        if excludingWeekends {
            let start = reset.addingTimeInterval(-duration)
            let totalWeekdayTime = weekdayTime(from: start, to: reset, calendar: calendar)
            // A period that lies entirely within a weekend keeps the linear fraction
            if totalWeekdayTime > 0 {
                let elapsedWeekdayTime = weekdayTime(from: start, to: now, calendar: calendar)
                fraction = min(max(elapsedWeekdayTime / totalWeekdayTime, 0), 1)
            }
        }

        return showRemaining ? 1.0 - fraction : fraction
    }

    /// Seconds between two dates that fall on weekdays, i.e. outside the weekend
    /// defined by the calendar's locale (Saturday and Sunday in most regions)
    /// - Parameters:
    ///   - start: Start of the interval
    ///   - end: End of the interval
    ///   - calendar: Calendar whose time zone and locale define days and weekend days
    /// - Returns: Weekday seconds in the interval, or 0 if `end` is not after `start`
    static func weekdayTime(from start: Date, to end: Date, calendar: Calendar) -> TimeInterval {
        var total: TimeInterval = 0
        var cursor = start
        // Walk day by day; day intervals follow DST, so 23- and 25-hour days are measured exactly
        while cursor < end, let day = calendar.dateInterval(of: .day, for: cursor), day.end > cursor {
            let segmentEnd = min(day.end, end)
            if !calendar.isDateInWeekend(cursor) {
                total += segmentEnd.timeIntervalSince(cursor)
            }
            cursor = segmentEnd
        }
        return total
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
