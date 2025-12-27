import XCTest
@testable import Claude_Usage

final class DateExtensionsTests: XCTestCase {

    // MARK: - Next Monday Tests

    func testNextMondayFromSunday() {
        // Sunday Dec 15, 2024 at 10:00 AM
        let sunday = createDate(year: 2024, month: 12, day: 15, hour: 10)
        let nextMonday = sunday.nextMonday1259pm()

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.weekday, from: nextMonday), 2) // Monday
        XCTAssertEqual(calendar.component(.hour, from: nextMonday), 12)
        XCTAssertEqual(calendar.component(.minute, from: nextMonday), 59)
    }

    func testNextMondayFromMonday() {
        // Monday Dec 16, 2024 at 10:00 AM - should go to NEXT Monday
        let monday = createDate(year: 2024, month: 12, day: 16, hour: 10)
        let nextMonday = monday.nextMonday1259pm()

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.weekday, from: nextMonday), 2) // Monday
        XCTAssertEqual(calendar.component(.day, from: nextMonday), 23) // Dec 23
    }

    func testNextMondayFromWednesday() {
        // Wednesday Dec 18, 2024
        let wednesday = createDate(year: 2024, month: 12, day: 18, hour: 10)
        let nextMonday = wednesday.nextMonday1259pm()

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.weekday, from: nextMonday), 2)
        XCTAssertEqual(calendar.component(.day, from: nextMonday), 23) // Dec 23
    }

    // MARK: - Time Remaining String Tests

    func testTimeRemainingHoursAndMinutes() {
        let now = Date()
        let future = now.addingTimeInterval(3 * 3600 + 45 * 60) // 3h 45m

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "3h 45m")
    }

    func testTimeRemainingHoursOnly() {
        let now = Date()
        let future = now.addingTimeInterval(2 * 3600) // 2h exactly

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "2h")
    }

    func testTimeRemainingMinutesOnly() {
        let now = Date()
        let future = now.addingTimeInterval(30 * 60) // 30m

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "30m")
    }

    func testTimeRemainingDays() {
        let now = Date()
        let future = now.addingTimeInterval(3 * 24 * 3600) // 3 days

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "3 days")
    }

    func testTimeRemainingOneDay() {
        let now = Date()
        let future = now.addingTimeInterval(25 * 3600) // 25 hours = 1 day

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "1 day")
    }

    func testTimeRemainingPast() {
        let now = Date()
        let past = now.addingTimeInterval(-3600) // 1 hour ago

        let result = past.timeRemainingString(from: now)
        XCTAssertEqual(result, "Reset now")
    }

    func testTimeRemainingLessThanMinute() {
        let now = Date()
        let future = now.addingTimeInterval(30) // 30 seconds

        let result = future.timeRemainingString(from: now)
        XCTAssertEqual(result, "< 1m")
    }

    // MARK: - Helpers

    private func createDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone.current

        return Calendar.current.date(from: components)!
    }
}
