import Foundation

/// Helper for consistent formatting throughout the app
enum FormatterHelper {
    /// Formats time until a reset (e.g., "in 2 hours", "in 3 days")
    static func timeUntilReset(from resetDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: resetDate, relativeTo: Date())
    }

    /// Abbreviates a non-negative count as K/M/B with one decimal (trailing .0 trimmed).
    /// e.g. 21_062_418 -> "21.1M", 1_000 -> "1K", 999 -> "999".
    static func abbreviatedCount(_ n: Int) -> String {
        func format(_ value: Double, _ suffix: String) -> String {
            let rounded = round(value * 10) / 10
            if rounded.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(rounded))\(suffix)"
            }
            return String(format: "%.1f%@", value, suffix)
        }
        let v = Double(n)

        if n >= 1_000_000_000 {
            return format(v / 1_000_000_000, "B")
        }

        if n >= 1_000_000 {
            let valueInThisTier = v / 1_000_000
            // If value would be >= 999.5 (approaches 1000), promote to B to avoid "1000.0M"
            if valueInThisTier >= 999.5 {
                return format(v / 1_000_000_000, "B")
            }
            return format(valueInThisTier, "M")
        }

        if n >= 1_000 {
            let valueInThisTier = v / 1_000
            // If value would be >= 999.5 (approaches 1000), promote to M to avoid "1000.0K"
            if valueInThisTier >= 999.5 {
                return format(v / 1_000_000, "M")
            }
            return format(valueInThisTier, "K")
        }

        return "\(n)"
    }
}
