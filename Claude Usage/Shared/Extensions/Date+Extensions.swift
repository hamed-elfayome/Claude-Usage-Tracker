import Foundation

extension Date {
    /// Returns the next Monday at 12:59pm in the specified timezone
    func nextMonday1259pm(in timezone: TimeZone = .current) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        // Get the current date components
        var components = calendar.dateComponents([.year, .month, .day, .weekday], from: self)

        // Calculate days until next Monday (weekday 2)
        let currentWeekday = components.weekday ?? 1
        let daysUntilMonday = currentWeekday == 2 ? 7 : (9 - currentWeekday) % 7

        // Create target date (next Monday)
        guard let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: self) else {
            return self
        }

        // Set time to 12:59pm
        components = calendar.dateComponents([.year, .month, .day], from: nextMonday)
        components.hour = 12
        components.minute = 59
        components.second = 0

        return calendar.date(from: components) ?? self
    }

    /// Returns a formatted time remaining string (e.g., "3h 45m" or "2 days")
    func timeRemainingString(from now: Date = Date()) -> String {
        let interval = self.timeIntervalSince(now)

        if interval < 0 {
            return "Reset now"
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let days = hours / 24

        if days > 0 {
            return days == 1 ? "1 day" : "\(days) days"
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }

    /// Returns a formatted reset time string (e.g., "Today 3:59am" or "Oct 28, 12:59pm")
    func resetTimeString(from now: Date = Date(), timezone: TimeZone = .current) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = timezone

        if calendar.isDateInToday(self) {
            formatter.dateFormat = "'Today' h:mma"
        } else if calendar.isDateInTomorrow(self) {
            formatter.dateFormat = "'Tomorrow' h:mma"
        } else {
            formatter.dateFormat = "MMM d, h:mma"
        }

        return formatter.string(from: self)
    }

    /// Returns time remaining rounded to full hours (e.g., "→2H", "→1H", "→<1H")
    func timeRemainingHoursString(from now: Date = Date()) -> String {
        let interval = self.timeIntervalSince(now)

        if interval <= 0 {
            return "→<1H"
        }

        // Less than 1 hour remaining
        if interval < 3600 {
            return "→<1H"
        }

        let hours = Int(ceil(interval / 3600))  // Round up to next hour
        return "→\(hours)H"
    }
}
