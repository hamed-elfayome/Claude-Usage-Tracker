import XCTest
@testable import Claude_Usage

final class DataStoreTests: XCTestCase {

    var dataStore: DataStore!

    override func setUp() {
        super.setUp()
        // Use shared instance - tests will use app group defaults
        dataStore = DataStore.shared
    }

    override func tearDown() {
        // Clean up test data
        dataStore.saveUsage(.empty)
        super.tearDown()
    }

    // MARK: - Usage Persistence Tests

    func testSaveAndLoadUsage() {
        let usage = createTestUsage(sessionPercentage: 42.5)

        dataStore.saveUsage(usage)
        let loaded = dataStore.loadUsage()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionPercentage, 42.5)
        XCTAssertEqual(loaded?.weeklyPercentage, 50)
    }

    func testLoadUsageWhenEmpty() {
        // Clear any existing data by saving empty
        dataStore.saveUsage(.empty)

        let loaded = dataStore.loadUsage()

        // Should return the empty usage we just saved
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionPercentage, 0)
    }

    // MARK: - Preferences Tests

    func testNotificationsEnabled() {
        dataStore.saveNotificationsEnabled(true)
        XCTAssertTrue(dataStore.loadNotificationsEnabled())

        dataStore.saveNotificationsEnabled(false)
        XCTAssertFalse(dataStore.loadNotificationsEnabled())
    }

    func testRefreshInterval() {
        dataStore.saveRefreshInterval(60.0)
        XCTAssertEqual(dataStore.loadRefreshInterval(), 60.0)

        dataStore.saveRefreshInterval(120.0)
        XCTAssertEqual(dataStore.loadRefreshInterval(), 120.0)
    }

    func testRefreshIntervalDefault() {
        // Save 0 to simulate unset
        dataStore.saveRefreshInterval(0)

        // Should return default (30 seconds from Constants)
        let loaded = dataStore.loadRefreshInterval()
        XCTAssertEqual(loaded, 30.0) // Constants.RefreshIntervals.menuBar
    }

    func testAutoStartSessionEnabled() {
        dataStore.saveAutoStartSessionEnabled(true)
        XCTAssertTrue(dataStore.loadAutoStartSessionEnabled())

        dataStore.saveAutoStartSessionEnabled(false)
        XCTAssertFalse(dataStore.loadAutoStartSessionEnabled())
    }

    // MARK: - Statusline Configuration Tests

    func testStatuslineShowDirectory() {
        dataStore.saveStatuslineShowDirectory(false)
        XCTAssertFalse(dataStore.loadStatuslineShowDirectory())

        dataStore.saveStatuslineShowDirectory(true)
        XCTAssertTrue(dataStore.loadStatuslineShowDirectory())
    }

    func testStatuslineShowBranch() {
        dataStore.saveStatuslineShowBranch(false)
        XCTAssertFalse(dataStore.loadStatuslineShowBranch())

        dataStore.saveStatuslineShowBranch(true)
        XCTAssertTrue(dataStore.loadStatuslineShowBranch())
    }

    // MARK: - Helpers

    private func createTestUsage(sessionPercentage: Double) -> ClaudeUsage {
        ClaudeUsage(
            sessionTokensUsed: Int(sessionPercentage * 1000),
            sessionLimit: 100000,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 500000,
            weeklyLimit: 1000000,
            weeklyPercentage: 50,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }
}
