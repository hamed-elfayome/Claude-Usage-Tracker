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

    /// Formats a date as a time string (e.g., "10:00 AM")
    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: Locale.current)
        return formatter.string(from: date)
    }
}
