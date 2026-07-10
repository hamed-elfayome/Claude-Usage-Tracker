import Foundation
import Combine

/// Detects whether the current time falls within Anthropic's peak hours
/// and publishes changes for SwiftUI reactivity.
final class PeakHoursService: ObservableObject {
    static let shared = PeakHoursService()

    // MARK: - Peak Window Configuration (single source of truth)
    // Change these if Anthropic updates the peak hours window.
    static let peakStartHour = 5   // 5:00 AM PT
    static let peakEndHour   = 11  // 11:00 AM PT (exclusive)
    static let peakTimeZone  = TimeZone(identifier: "America/Los_Angeles")!

    @Published private(set) var isPeakHours: Bool = false

    private var timer: Timer?

    private init() {
        isPeakHours = PeakHoursService.checkIsPeakHours()
    }

    /// Call once from MenuBarManager setup. Evaluates immediately and starts a 60s timer.
    func start() {
        isPeakHours = PeakHoursService.checkIsPeakHours()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            let peak = PeakHoursService.checkIsPeakHours()
            if self?.isPeakHours != peak {
                self?.isPeakHours = peak
            }
        }
        timer?.tolerance = 10
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks if `date` falls within the peak hours window (weekdays only).
    static func checkIsPeakHours(at date: Date = Date()) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = peakTimeZone
        let components = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = components.weekday, let hour = components.hour else { return false }
        let isWeekday = weekday >= 2 && weekday <= 6
        let isInWindow = hour >= peakStartHour && hour < peakEndHour
        return isWeekday && isInWindow
    }

    /// Returns the end time of the current peak window, or nil if not peak.
    static func peakEndDate() -> Date? {
        var ptCalendar = Calendar.current
        ptCalendar.timeZone = peakTimeZone
        let today = ptCalendar.dateComponents([.year, .month, .day], from: Date())
        var endComponents = today
        endComponents.hour = peakEndHour
        endComponents.minute = 0
        endComponents.second = 0
        return ptCalendar.date(from: endComponents)
    }

    /// Returns the peak hours window in the user's local timezone, e.g. "3:00 PM – 9:00 PM GST".
    static func localTimeRangeString() -> String {
        let local = TimeZone.current
        var ptCalendar = Calendar.current
        ptCalendar.timeZone = peakTimeZone
        let today = ptCalendar.dateComponents([.year, .month, .day], from: Date())

        var startComponents = today
        startComponents.hour = peakStartHour
        startComponents.minute = 0
        var endComponents = today
        endComponents.hour = peakEndHour
        endComponents.minute = 0

        guard let startDate = ptCalendar.date(from: startComponents),
              let endDate = ptCalendar.date(from: endComponents) else {
            return "\(peakStartHour):00 AM – \(peakEndHour):00 AM PT"
        }

        let formatter = DateFormatter()
        formatter.timeZone = local
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm a"

        let localAbbrev = local.abbreviation() ?? local.identifier
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate)) \(localAbbrev)"
    }
}
