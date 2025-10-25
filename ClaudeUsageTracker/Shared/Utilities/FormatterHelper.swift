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
}
