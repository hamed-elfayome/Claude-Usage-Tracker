import XCTest
@testable import Claude_Usage

final class SupportReminderServiceTests: XCTestCase {

    private let service = SupportReminderService.shared
    private let day: TimeInterval = 86_400

    func testNotDueWithinFirstWeek() {
        let install = Date()
        let now = install.addingTimeInterval(6 * day)
        XCTAssertFalse(service.isDue(now: now, firstLaunch: install, lastShown: nil))
    }

    func testDueAfterFirstWeekWhenNeverShown() {
        let install = Date()
        let now = install.addingTimeInterval(8 * day)
        XCTAssertTrue(service.isDue(now: now, firstLaunch: install, lastShown: nil))
    }

    func testNotDueAgainWithinThirtyDaysOfLastShow() {
        let install = Date()
        let lastShown = install.addingTimeInterval(10 * day)
        let now = lastShown.addingTimeInterval(29 * day)
        XCTAssertFalse(service.isDue(now: now, firstLaunch: install, lastShown: lastShown))
    }

    func testDueAgainAfterThirtyDays() {
        let install = Date()
        let lastShown = install.addingTimeInterval(10 * day)
        let now = lastShown.addingTimeInterval(31 * day)
        XCTAssertTrue(service.isDue(now: now, firstLaunch: install, lastShown: lastShown))
    }
}
