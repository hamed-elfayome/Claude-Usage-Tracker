import XCTest
@testable import Claude_Usage

final class ClaudeAPIServiceParsingTests: XCTestCase {
    private let service = ClaudeAPIService()

    // MARK: - parseUsageResponse

    func testUltraResponseWithNullFiveHourHasNoSessionLimit() throws {
        // Trimmed Ultra response from issue #356: five_hour is null and
        // limits[] only carries weekly entries.
        let json = #"""
        {
          "five_hour": null,
          "seven_day": {
            "utilization": 47.0,
            "resets_at": "2026-11-03T17:00:00.036205+00:00"
          },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "seven_day_omelette": null,
          "limits": [
            {
              "kind": "weekly_all",
              "group": "weekly",
              "percent": 47,
              "severity": "normal",
              "resets_at": "2026-11-03T17:00:00.036205+00:00",
              "scope": null,
              "is_active": true
            },
            {
              "kind": "weekly_scoped",
              "group": "weekly",
              "percent": 2,
              "severity": "normal",
              "resets_at": "2026-11-03T17:00:00.036349+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
              "is_active": false
            }
          ]
        }
        """#

        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertFalse(usage.hasSessionLimit)
        XCTAssertEqual(usage.weeklyPercentage, 47)
        // 2026-11-03T17:00:00Z
        XCTAssertEqual(usage.weeklyResetTime.timeIntervalSince1970, 1_793_725_200, accuracy: 1)
    }

    func testFreePlanResponseWithEverythingNullReportsNoLimits() throws {
        // Free-plan response from issue #312: every window is null and limits[] is empty.
        let json = #"""
        {"five_hour":null,"seven_day":null,"seven_day_opus":null,"seven_day_sonnet":null,
         "seven_day_omelette":null,"extra_usage":null,"limits":[],"spend":null}
        """#
        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertFalse(usage.hasSessionLimit)
        XCTAssertFalse(usage.hasWeeklyLimit)
    }

    func testEnterpriseMemberSpendLimitIsParsed() throws {
        // Enterprise seat with no usage windows but an org-set monthly spend
        // limit; the spend object as claude.ai returns it.
        let json = #"""
        {"five_hour":null,"seven_day":null,"limits":[],
         "spend":{"used":{"amount_minor":11359,"currency":"usd","exponent":2},
                  "limit":{"amount_minor":50000,"currency":"USD","exponent":2},
                  "percent":23,"severity":"normal","enabled":true,
                  "cap":{"money":null,"credits":{"amount_minor":50000,"exponent":2}}}}
        """#
        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertFalse(usage.hasWeeklyLimit)
        XCTAssertEqual(usage.personalSpendLimit, 50_000)
        XCTAssertEqual(usage.personalSpendUsed, 11_359)
        XCTAssertEqual(usage.personalSpendCurrency, "USD")
        XCTAssertEqual(usage.effectiveMonthlySpendLimit(targetCents: nil), 50_000)
        // A target the user set takes priority over the organization's limit.
        XCTAssertEqual(usage.effectiveMonthlySpendLimit(targetCents: 100_000), 100_000)

        let percentage = try XCTUnwrap(usage.reportedMonthlySpendPercentage(targetCents: nil))
        XCTAssertEqual(percentage, 22.718, accuracy: 0.001)
    }

    func testReportedMonthlySpendPercentageNeedsAnOrganizationLimit() {
        var usage = ClaudeUsage.empty
        usage.hasSessionLimit = false
        usage.hasWeeklyLimit = false
        usage.personalSpendUsed = 11_359
        // A user's own target alone isn't a reported limit.
        XCTAssertNil(usage.reportedMonthlySpendPercentage(targetCents: 50_000))

        usage.personalSpendLimit = 50_000
        XCTAssertNotNil(usage.reportedMonthlySpendPercentage(targetCents: nil))

        // Plans that report a weekly limit keep the weekly reading.
        usage.hasWeeklyLimit = true
        XCTAssertNil(usage.reportedMonthlySpendPercentage(targetCents: nil))
    }

    func testCurrentMonthWindowSpansTheCalendarMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 12)))
        let window = try XCTUnwrap(ClaudeUsage.currentMonthWindow(now: now, calendar: calendar))
        XCTAssertEqual(window.resetTime, calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(window.duration, 28 * 24 * 3600)
    }

    func testSpendWithoutLimitLeavesPersonalSpendUnset() throws {
        // Personal plans report spend with a null limit; no Monthly Spend row.
        let json = #"""
        {"five_hour":null,"seven_day":{"utilization":27,"resets_at":"2026-11-29T15:00:00.552176+00:00"},
         "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"enabled":false}}
        """#
        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertNil(usage.personalSpendLimit)
        XCTAssertNil(usage.personalSpendUsed)
    }

    func testUltraResponseStillHasAWeeklyLimit() throws {
        let json = #"""
        {"five_hour":null,"seven_day":{"utilization":47.0,"resets_at":"2026-11-03T17:00:00.036205+00:00"},"limits":[]}
        """#
        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertFalse(usage.hasSessionLimit)
        XCTAssertTrue(usage.hasWeeklyLimit)
    }

    func testUsageSavedBeforeTheWeeklyFlagExistedKeepsItsWeeklyRow() throws {
        var usage = ClaudeUsage.empty
        usage.hasWeeklyLimit = false
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(usage)) as? [String: Any])
        object.removeValue(forKey: "hasWeeklyLimit")
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertTrue(decoded.hasWeeklyLimit)
    }

    func testResponseWithFiveHourKeepsSessionValues() throws {
        let json = #"""
        {
          "five_hour": { "utilization": 32, "resets_at": "2026-11-02T15:00:00.000000+00:00" },
          "seven_day": { "utilization": 12.5, "resets_at": "2026-11-03T17:00:00.000000+00:00" },
          "limits": [
            { "kind": "session", "group": "session", "percent": 32,
              "resets_at": "2026-11-02T15:00:00.000000+00:00", "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 12,
              "resets_at": "2026-11-03T17:00:00.000000+00:00", "scope": null }
          ]
        }
        """#

        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertTrue(usage.hasSessionLimit)
        XCTAssertEqual(usage.sessionPercentage, 32)
        // 2026-11-02T15:00:00Z
        XCTAssertEqual(usage.sessionResetTime.timeIntervalSince1970, 1_793_631_600, accuracy: 1)
        XCTAssertEqual(usage.weeklyPercentage, 12.5)
    }

    func testNullFiveHourWithNonWeeklyLimitStillHasSessionLimit() throws {
        // Guards against an API that nulls five_hour for every plan and
        // reports the session window in limits[] instead.
        let json = #"""
        {
          "five_hour": null,
          "seven_day": { "utilization": 20, "resets_at": "2026-11-03T17:00:00.000000+00:00" },
          "limits": [
            { "kind": "session", "group": "session", "percent": 40,
              "resets_at": "2026-11-02T15:00:00.000000+00:00", "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 20,
              "resets_at": "2026-11-03T17:00:00.000000+00:00", "scope": null }
          ]
        }
        """#

        let usage = try service.parseUsageResponse(Data(json.utf8))

        XCTAssertTrue(usage.hasSessionLimit)
    }

    // MARK: - parseUsageFromRateLimitHeaders

    func testHeadersWithoutFiveHourWindowHaveNoSessionLimit() throws {
        let response = try makeResponse(headers: [
            "anthropic-ratelimit-unified-7d-utilization": "0.47",
            "anthropic-ratelimit-unified-7d-reset": "1793725200"
        ])

        let usage = service.parseUsageFromRateLimitHeaders(response)

        XCTAssertFalse(usage.hasSessionLimit)
        XCTAssertEqual(usage.weeklyPercentage, 47, accuracy: 0.001)
        XCTAssertEqual(usage.weeklyResetTime.timeIntervalSince1970, 1_793_725_200)
    }

    func testHeadersWithFiveHourWindowKeepSessionValues() throws {
        let sessionReset = Date().addingTimeInterval(2 * 3600).timeIntervalSince1970.rounded()
        let response = try makeResponse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.32",
            "anthropic-ratelimit-unified-5h-reset": String(Int(sessionReset)),
            "anthropic-ratelimit-unified-7d-utilization": "0.12",
            "anthropic-ratelimit-unified-7d-reset": "1793725200"
        ])

        let usage = service.parseUsageFromRateLimitHeaders(response)

        XCTAssertTrue(usage.hasSessionLimit)
        XCTAssertEqual(usage.sessionPercentage, 32, accuracy: 0.001)
        XCTAssertEqual(usage.sessionResetTime.timeIntervalSince1970, sessionReset)
        XCTAssertEqual(usage.weeklyPercentage, 12, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeResponse(headers: [String: String]) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        ))
    }
}
