import XCTest
@testable import Claude_Usage

final class SessionPlanningServiceTests: XCTestCase {

    func testRecommendedLeadTimeCalculation() {
        // 1.5 hours to limit = 90 min
        // Recommended lead time = 5h - 1.5h = 3.5h = 210 min
        let typicalTTL: TimeInterval = 1.5 * 60 * 60
        let leadTime = Constants.sessionWindow - typicalTTL
        XCTAssertEqual(leadTime, 3.5 * 60 * 60, accuracy: 1)

        // 2 hours to limit = 120 min
        // Recommended lead time = 5h - 2h = 3h = 180 min
        let typicalTTL2: TimeInterval = 2 * 60 * 60
        let leadTime2 = Constants.sessionWindow - typicalTTL2
        XCTAssertEqual(leadTime2, 3 * 60 * 60, accuracy: 1)

        // 2.5 hours to limit = 150 min
        // Recommended lead time = 5h - 2.5h = 2.5h = 150 min
        let typicalTTL3: TimeInterval = 2.5 * 60 * 60
        let leadTime3 = Constants.sessionWindow - typicalTTL3
        XCTAssertEqual(leadTime3, 2.5 * 60 * 60, accuracy: 1)
    }

    func testRecommendedPingTime() {
        let plannedWorkStart = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let typicalTTL: TimeInterval = 2 * 60 * 60 // 2 hours
        let leadTime = Constants.sessionWindow - typicalTTL // 3 hours
        let expectedPingTime = plannedWorkStart.addingTimeInterval(-leadTime)

        XCTAssertEqual(expectedPingTime, Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!)
    }

    func testPingTimeAcrossDayBoundary() {
        let plannedWorkStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let typicalTTL: TimeInterval = 1 * 60 * 60 // 1 hour
        let leadTime = Constants.sessionWindow - typicalTTL // 4 hours
        let pingTime = plannedWorkStart.addingTimeInterval(-leadTime)

        // Should be 4:00 AM same day
        let components = Calendar.current.dateComponents([.hour, .minute], from: pingTime)
        XCTAssertEqual(components.hour, 4)
        XCTAssertEqual(components.minute, 0)
    }

    func testManualDurationClamping() {
        let belowMin = SessionPlanningSettings(manualTypicalTimeToLimitMinutes: 5)
        XCTAssertGreaterThanOrEqual(belowMin.manualTypicalTimeToLimitMinutes, Constants.SessionPlanning.minTimeToLimitMinutes)

        let aboveMax = SessionPlanningSettings(manualTypicalTimeToLimitMinutes: 400)
        XCTAssertLessThanOrEqual(aboveMax.manualTypicalTimeToLimitMinutes, Constants.SessionPlanning.maxTimeToLimitMinutes)

        let withinRange = SessionPlanningSettings(manualTypicalTimeToLimitMinutes: 120)
        XCTAssertEqual(withinRange.manualTypicalTimeToLimitMinutes, 120)
    }

    func testEstimatedSessionStart() {
        let resetTime = Date().addingTimeInterval(3600) // 1 hour from now
        let estimatedStart = resetTime.addingTimeInterval(-Constants.sessionWindow)
        XCTAssertEqual(estimatedStart.timeIntervalSinceNow, -Constants.sessionWindow + 3600, accuracy: 1)
    }

    func testSecondSessionAvailableTime() {
        let pingTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let secondSessionTime = pingTime.addingTimeInterval(Constants.sessionWindow)
        let components = Calendar.current.dateComponents([.hour, .minute], from: secondSessionTime)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    func testBackwardCompatibleSessionPlanningSettingsDecoding() throws {
        // Simulate older JSON without sessionPlanningSettings
        let oldJSON = """
        {
            "isEnabled": false,
            "repeatBehavior": "weekdays",
            "useAutoEstimate": true,
            "manualTypicalTimeToLimitMinutes": 120,
            "remindersEnabled": true,
            "autoPingEnabled": false,
            "wasteWarningEnabled": true,
            "planModeTipsEnabled": true
        }
        """

        let data = oldJSON.data(using: .utf8)!
        let settings = try JSONDecoder().decode(SessionPlanningSettings.self, from: data)
        XCTAssertFalse(settings.isEnabled)
    }

    func testSessionPlanningSettingsWithTipPreferencesDecoding() throws {
        let json = """
        {
            "isEnabled": true,
            "repeatBehavior": "weekdays",
            "useAutoEstimate": true,
            "manualTypicalTimeToLimitMinutes": 120,
            "remindersEnabled": true,
            "autoPingEnabled": false,
            "wasteWarningEnabled": true,
            "planModeTipsEnabled": true,
            "tipPreferences": {
                "showClaudeAITips": true,
                "showClaudeCodeTips": true,
                "showCoworkTips": true,
                "peakHoursReminders": true
            }
        }
        """

        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(SessionPlanningSettings.self, from: data)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.tipPreferences.showClaudeAITips)
    }
}