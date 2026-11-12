import XCTest
@testable import Claude_Usage

final class UsageStatusCalculatorTests: XCTestCase {

    // MARK: - Used-Based Thresholds (showRemaining = false)

    func testUsedBasedThresholds_Safe() {
        // 0-69% used should be safe (green)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 0, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 50, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 69, showRemaining: false),
            .safe
        )
    }

    func testUsedBasedThresholds_Moderate() {
        // 70-89% used should be moderate (yellow)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 70, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 85, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 89, showRemaining: false),
            .moderate
        )
    }

    func testUsedBasedThresholds_Critical() {
        // 90-100% used should be critical (red)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90, showRemaining: false),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 95, showRemaining: false),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 100, showRemaining: false),
            .critical
        )
    }

    // MARK: - Remaining-Based Thresholds (showRemaining = true)

    func testRemainingBasedThresholds_Safe() {
        // >=30% remaining (0-70% used) should be safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 0, showRemaining: true),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 50, showRemaining: true),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 70, showRemaining: true),
            .safe
        )
    }

    func testRemainingBasedThresholds_Moderate() {
        // 10-29% remaining (71-90% used) should be moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 71, showRemaining: true),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 85, showRemaining: true),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90, showRemaining: true),
            .moderate
        )
    }

    func testRemainingBasedThresholds_Critical() {
        // <10% remaining (>90% used) should be critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 91, showRemaining: true),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 95, showRemaining: true),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 100, showRemaining: true),
            .critical
        )
    }

    // MARK: - Display Percentage Calculation

    func testGetDisplayPercentage_UsedMode() {
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 65, showRemaining: false),
            65.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 0, showRemaining: false),
            0.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 100, showRemaining: false),
            100.0
        )
    }

    func testGetDisplayPercentage_RemainingMode() {
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 65, showRemaining: true),
            35.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 0, showRemaining: true),
            100.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 100, showRemaining: true),
            0.0
        )
    }

    // MARK: - Edge Cases

    func testBoundaryConditions_UsedMode() {
        // Test exact boundary values for used-based thresholds
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 69.9, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 70.0, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 89.9, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90.0, showRemaining: false),
            .critical
        )
    }

    func testBoundaryConditions_RemainingMode() {
        // Test exact boundary values for remaining-based thresholds
        // 31% remaining (69% used) = safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 69, showRemaining: true),
            .safe
        )
        // 30% remaining (70% used) = safe (30 is included in 30... range)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 70, showRemaining: true),
            .safe
        )
        // 29% remaining (71% used) = moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 71, showRemaining: true),
            .moderate
        )
        // 10% remaining (90% used) = moderate (10 is included in 10..<30 range)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90, showRemaining: true),
            .moderate
        )
        // 9% remaining (91% used) = critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 91, showRemaining: true),
            .critical
        )
    }

    func testNegativePercentage() {
        // Should handle negative used percentages gracefully (edge case, shouldn't happen in practice)
        // With -10% used, remaining would be 110%, clamped to 110 (max doesn't apply here)
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: -10, showRemaining: true),
            110.0  // max(0, 100 - (-10)) = max(0, 110) = 110
        )
    }

    func testOverOneHundredPercentage() {
        // Should handle over 100% gracefully
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 110, showRemaining: true),
            0.0  // max(0, 100 - 110) = 0
        )
    }

    // MARK: - Elapsed Fraction Excluding Weekends

    func testExcludingWeekends_FridayNightIsHalfwayThroughWorkWeek() {
        // Weekly reset on Wednesday at noon: by Friday midnight 2.5 of the 5 weekdays have passed
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)  // Wednesday
        let fridayMidnight = makeDate(calendar, month: 9, day: 12)

        XCTAssertEqual(weeklyFraction(reset: reset, now: fridayMidnight, calendar: calendar), 0.5, accuracy: 1e-9)
        // Counting weekends, only 2.5 of 7 days have passed
        XCTAssertEqual(
            weeklyFraction(reset: reset, now: fridayMidnight, calendar: calendar, excludingWeekends: false),
            2.5 / 7,
            accuracy: 1e-9
        )
    }

    func testExcludingWeekends_HoldsStillOverWeekend() {
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)
        let saturdayMorning = makeDate(calendar, month: 9, day: 12, hour: 9)
        let sundayNight = makeDate(calendar, month: 9, day: 13, hour: 23)
        let mondayMidnight = makeDate(calendar, month: 9, day: 14)

        for now in [saturdayMorning, sundayNight, mondayMidnight] {
            XCTAssertEqual(weeklyFraction(reset: reset, now: now, calendar: calendar), 0.5, accuracy: 1e-9)
        }
    }

    func testExcludingWeekends_AdvancesOnWeekdays() {
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)
        let thursdayMidnight = makeDate(calendar, month: 9, day: 10)
        let mondayNoon = makeDate(calendar, month: 9, day: 14, hour: 12)
        let wednesdayMidnight = makeDate(calendar, month: 9, day: 16)

        XCTAssertEqual(weeklyFraction(reset: reset, now: thursdayMidnight, calendar: calendar), 0.1, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: mondayNoon, calendar: calendar), 0.6, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: wednesdayMidnight, calendar: calendar), 0.9, accuracy: 1e-9)
    }

    func testExcludingWeekends_ResetDuringWeekend() {
        // Reset on Sunday at 10:00: the fraction stays at 0 until Monday and reaches 1 by Saturday
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 13, hour: 10)
        let sundayEvening = makeDate(calendar, month: 9, day: 6, hour: 20)
        let mondayNoon = makeDate(calendar, month: 9, day: 7, hour: 12)
        let saturdayMorning = makeDate(calendar, month: 9, day: 12, hour: 9)

        XCTAssertEqual(weeklyFraction(reset: reset, now: sundayEvening, calendar: calendar), 0.0, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: mondayNoon, calendar: calendar), 0.1, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: saturdayMorning, calendar: calendar), 1.0, accuracy: 1e-9)
    }

    func testExcludingWeekends_ShowRemainingInverts() {
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)
        let mondayNoon = makeDate(calendar, month: 9, day: 14, hour: 12)

        XCTAssertEqual(
            weeklyFraction(reset: reset, now: mondayNoon, calendar: calendar, showRemaining: true),
            0.4,
            accuracy: 1e-9
        )
    }

    func testExcludingWeekends_ExpiredOrMissingReset() {
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)
        let afterReset = makeDate(calendar, month: 9, day: 17)

        XCTAssertEqual(weeklyFraction(reset: reset, now: afterReset, calendar: calendar), 1.0)
        XCTAssertEqual(weeklyFraction(reset: reset, now: afterReset, calendar: calendar, showRemaining: true), 0.0)
        XCTAssertNil(UsageStatusCalculator.elapsedFraction(
            resetTime: nil,
            duration: 7 * 24 * 60 * 60,
            showRemaining: false,
            excludingWeekends: true
        ))
    }

    func testExcludingWeekends_FollowsRegionalWeekend() {
        // In Israel the weekend is Friday–Saturday, so Sunday counts as a weekday
        let calendar = makeCalendar(timeZone: "Asia/Jerusalem", locale: "he_IL")
        let reset = makeDate(calendar, month: 9, day: 16, hour: 12)
        let sundayMidnight = makeDate(calendar, month: 9, day: 13)
        let sundayNoon = makeDate(calendar, month: 9, day: 13, hour: 12)

        // Half of Wednesday and all of Thursday: 36 of the 120 weekday hours
        XCTAssertEqual(weeklyFraction(reset: reset, now: sundayMidnight, calendar: calendar), 36.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: sundayNoon, calendar: calendar), 48.0 / 120.0, accuracy: 1e-9)
    }

    func testExcludingWeekends_HandlesDaylightSavingTransition() {
        // Paris falls back an hour on Sunday Oct 25, 2026: the 168-hour window
        // opens Wednesday at 13:00 CEST and holds 119 weekday hours
        let calendar = makeCalendar()
        let reset = makeDate(calendar, month: 10, day: 28, hour: 12)
        let saturdayMidnight = makeDate(calendar, month: 10, day: 24)
        let mondayMidnight = makeDate(calendar, month: 10, day: 26)
        let expected = 59.0 / 119.0  // 11h on Wednesday + Thursday + Friday

        XCTAssertEqual(weeklyFraction(reset: reset, now: saturdayMidnight, calendar: calendar), expected, accuracy: 1e-9)
        XCTAssertEqual(weeklyFraction(reset: reset, now: mondayMidnight, calendar: calendar), expected, accuracy: 1e-9)
    }

    func testWeekdayTime_SkipsWeekendDays() {
        let calendar = makeCalendar()
        let fridayNoon = makeDate(calendar, month: 9, day: 11, hour: 12)
        let saturdayNoon = makeDate(calendar, month: 9, day: 12, hour: 12)
        let sundayNoon = makeDate(calendar, month: 9, day: 13, hour: 12)
        let mondayNoon = makeDate(calendar, month: 9, day: 14, hour: 12)

        XCTAssertEqual(
            UsageStatusCalculator.weekdayTime(from: fridayNoon, to: mondayNoon, calendar: calendar),
            24 * 60 * 60,
            accuracy: 1e-6
        )
        XCTAssertEqual(UsageStatusCalculator.weekdayTime(from: saturdayNoon, to: sundayNoon, calendar: calendar), 0)
        XCTAssertEqual(UsageStatusCalculator.weekdayTime(from: mondayNoon, to: fridayNoon, calendar: calendar), 0)
    }

    // MARK: - Helpers

    /// Gregorian calendar pinned to a time zone and locale, so weekend days are deterministic
    private func makeCalendar(timeZone: String = "Europe/Paris", locale: String = "en_US") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    private func makeDate(_ calendar: Calendar, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Elapsed fraction of a 7-day window, or NaN (which fails any comparison) when unavailable
    private func weeklyFraction(
        reset: Date,
        now: Date,
        calendar: Calendar,
        excludingWeekends: Bool = true,
        showRemaining: Bool = false
    ) -> Double {
        UsageStatusCalculator.elapsedFraction(
            resetTime: reset,
            duration: 7 * 24 * 60 * 60,
            showRemaining: showRemaining,
            excludingWeekends: excludingWeekends,
            now: now,
            calendar: calendar
        ) ?? .nan
    }
}
