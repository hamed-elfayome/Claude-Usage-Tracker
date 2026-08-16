import XCTest
@testable import Claude_Usage

final class ZaiUsageTests: XCTestCase {
    private func makeQuotaBody(
        level: String? = "pro",
        limits: [[String: Any]] = [
            [
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "usage": 2000.0,
                "currentValue": 500.0,
                "remaining": 1500.0,
                "percentage": 25.0,
                "nextResetTime": 1_755_000_000_000
            ],
            [
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "usage": 10_000.0,
                "currentValue": 2_500.0,
                "percentage": 25.0,
                "nextResetTime": 1_755_100_000_000
            ],
            [
                "type": "TIME_LIMIT",
                "unit": 5,
                "usage": 300.0,
                "currentValue": 30.0,
                "percentage": 10.0,
                "nextResetTime": 1_755_200_000_000
            ]
        ]
    ) -> [String: Any] {
        var body: [String: Any] = [
            "code": 0,
            "msg": "ok",
            "success": true
        ]
        if let level {
            body["data"] = ["level": level, "limits": limits] as [String: Any]
        }
        return body
    }

    private func encode(_ json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Parsing

    func testParsesQuotaLimitResponse() throws {
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody()),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(snapshot.account?.planType, "pro")
        XCTAssertEqual(snapshot.rateLimits.count, 3)

        let fiveHour = snapshot.rateLimit(preferredID: "TOKENS_LIMIT-3")
        XCTAssertEqual(fiveHour?.primary?.usedPercent, 25.0)
        XCTAssertEqual(fiveHour?.primary?.windowDurationMinutes, 300)
        XCTAssertEqual(fiveHour?.primary?.usedCredits, 500.0)
        XCTAssertEqual(fiveHour?.primary?.totalCredits, 2000.0)
        XCTAssertEqual(
            try XCTUnwrap(fiveHour?.primary?.resetsAt).timeIntervalSince1970,
            1_755_000_000,
            accuracy: 0.5
        )
        XCTAssertEqual(fiveHour?.kind, .tokens)

        let weekly = snapshot.rateLimit(preferredID: "TOKENS_LIMIT-6")
        XCTAssertEqual(weekly?.primary?.windowDurationMinutes, 7 * 24 * 60)

        let tools = snapshot.rateLimit(preferredID: "TIME_LIMIT-5")
        XCTAssertEqual(tools?.kind, .toolCalls)
        XCTAssertEqual(snapshot.lastUpdated.timeIntervalSince1970, 1_000)
    }

    func testPrimaryRateLimitPrefersFiveHourTokenWindow() throws {
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody()),
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.primaryRateLimit?.id, ZAIRateLimit.fiveHourTokensID)
    }

    func testDerivesPercentageWhenMissing() throws {
        let onlyFiveHour: [[String: Any]] = [
            [
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "usage": 2_000.0,
                "currentValue": 500.0
            ]
        ]
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody(limits: onlyFiveHour)),
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.primaryRateLimit?.primary?.usedPercent, 25.0)
    }

    func testRejectsUnrecognizedBodyWithoutReplacingCachedUsage() {
        XCTAssertThrowsError(
            try ZAIAPIService.parse(data: Data("not json".utf8), fetchedAt: Date())
        ) { error in
            guard case ZAIAPIServiceError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testBodyLevelAuthFailureMapsToInvalidKey() throws {
        let body: [String: Any] = [
            "code": 1001,
            "msg": "invalid api key",
            "success": false
        ]
        XCTAssertThrowsError(
            try ZAIAPIService.parse(data: try encode(body), fetchedAt: Date())
        ) { error in
            guard case ZAIAPIServiceError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }

    func testBodyLevelExpiredPlanMapsToInvalidKey() throws {
        let body: [String: Any] = [
            "code": 1309,
            "msg": "plan expired",
            "success": false
        ]
        XCTAssertThrowsError(
            try ZAIAPIService.parse(data: try encode(body), fetchedAt: Date())
        ) { error in
            guard case ZAIAPIServiceError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }

    func testBodyLevelCodingPlanMessageMapsToNoCodingPlan() throws {
        let body: [String: Any] = [
            "code": 1234,
            "msg": "no coding plan found",
            "success": false
        ]
        XCTAssertThrowsError(
            try ZAIAPIService.parse(data: try encode(body), fetchedAt: Date())
        ) { error in
            guard case ZAIAPIServiceError.noCodingPlan = error else {
                return XCTFail("Expected noCodingPlan, got \(error)")
            }
        }
    }

    // MARK: - HTTP layer (injected transport)

    private func makeService(
        status: Int,
        body: [String: Any]
    ) throws -> ZAIAPIService {
        let data = try encode(body)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: ZAIAPIService.defaultBaseURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        ))
        return ZAIAPIService(
            dataProvider: { _ in (data, response) }
        )
    }

    func testHTTPUnauthorizedMapsToInvalidKey() async throws {
        let service = try makeService(status: 401, body: [:])
        do {
            _ = try await service.fetchUsage(apiKey: "key")
            XCTFail("Expected invalidKey")
        } catch {
            guard case ZAIAPIServiceError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }

    func testSuccessfulHTTPResponseProducesSnapshot() async throws {
        let service = try makeService(status: 200, body: makeQuotaBody())
        let snapshot = try await service.fetchUsage(apiKey: "key")
        XCTAssertEqual(snapshot.primaryRateLimit?.primary?.usedPercent, 25.0)
    }

    func testEmptyAPIKeyIsRejectedBeforeNetworking() async throws {
        let service = try makeService(status: 200, body: makeQuotaBody())
        do {
            _ = try await service.fetchUsage(apiKey: "   ")
            XCTFail("Expected invalidKey")
        } catch {
            guard case ZAIAPIServiceError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }

    // MARK: - Models

    func testZAIUsageRoundTripsThroughCodable() throws {
        let snapshot = ZAIUsage(
            account: ZAIAccount(planType: "max"),
            rateLimits: [
                ZAIRateLimit(
                    id: ZAIRateLimit.fiveHourTokensID,
                    name: "Tokens · 5-hour window",
                    kind: .tokens,
                    primary: ZAIRateLimitWindow(
                        usedPercent: 42,
                        windowDurationMinutes: 300,
                        resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                        usedCredits: 8_400,
                        totalCredits: 28_000
                    )
                )
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_500_000_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ZAIUsage.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testZAIProfileConfigurationBackwardCompatibleDefaults() throws {
        let data = try JSONEncoder().encode([String: String]())
        let decoded = try JSONDecoder().decode(ZAIProfileConfiguration.self, from: data)
        XCTAssertNil(decoded.selectedLimitID)
    }

    func testZAIProfileRoundTripsProviderConfigAndUsage() throws {
        var profile = Profile(name: "GLM", provider: .zai)
        profile.zaiAPIKey = "secret-key"
        profile.zaiConfiguration = ZAIProfileConfiguration(selectedLimitID: "TOKENS_LIMIT-6")
        profile.zaiUsage = ZAIUsage(
            account: ZAIAccount(planType: "lite"),
            rateLimits: [],
            lastUpdated: Date(timeIntervalSince1970: 1_234_567)
        )

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: encoded)

        // Secrets are never written to the plist encoding.
        XCTAssertNil(decoded.zaiAPIKey)
        XCTAssertEqual(decoded.provider, .zai)
        XCTAssertEqual(decoded.zaiConfiguration.selectedLimitID, "TOKENS_LIMIT-6")
        XCTAssertEqual(decoded.zaiUsage?.account?.planType, "lite")
        XCTAssertTrue(decoded.hasUsageCredentials == false)
    }

    func testLegacyProfileDefaultsToClaudeProviderWithoutZaiFields() throws {
        let legacy: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Old",
            "iconConfig": ["showIconNames": true, "metrics": []]
        ]
        let profile = try JSONDecoder().decode(
            Profile.self,
            from: try JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(profile.provider, .claude)
        XCTAssertNil(profile.zaiUsage)
        XCTAssertEqual(profile.zaiConfiguration, ZAIProfileConfiguration())
    }

    // MARK: - Menu bar configuration back-compat

    func testLegacyMenuBarConfigurationGainsDisabledZaiMetric() throws {
        let original = MenuBarIconConfiguration.default
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var metrics = try XCTUnwrap(json["metrics"] as? [[String: Any]])
        metrics.removeAll { $0["metricType"] as? String == MenuBarMetricType.zai.rawValue }
        json["metrics"] = metrics

        let decoded = try JSONDecoder().decode(
            MenuBarIconConfiguration.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )

        let zaiMetric = try XCTUnwrap(decoded.config(for: .zai))
        XCTAssertFalse(zaiMetric.isEnabled)
        XCTAssertEqual(zaiMetric.order, 4)
    }

    func testZaiProfileDefaultEnablesOnlyZaiMetric() {
        let config = MenuBarIconConfiguration.zaiProfileDefault
        XCTAssertTrue(config.config(for: .zai)?.isEnabled ?? false)
        XCTAssertFalse(config.enabledMetrics.contains { $0.metricType != .zai })
    }

    // MARK: - Selection helpers

    func testPreferredRateLimitFallsBackToFiveHourWindow() throws {
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody()),
            fetchedAt: Date()
        )
        XCTAssertEqual(
            snapshot.rateLimit(preferredID: "does-not-exist")?.id,
            ZAIRateLimit.fiveHourTokensID
        )
        XCTAssertEqual(
            snapshot.rateLimit(preferredID: "TOKENS_LIMIT-6")?.id,
            "TOKENS_LIMIT-6"
        )
    }

    func testWindowClassifiersDistinguishSessionWeeklyAndTools() throws {
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody()),
            fetchedAt: Date()
        )

        let fiveHour = try XCTUnwrap(snapshot.rateLimit(preferredID: "TOKENS_LIMIT-3"))
        XCTAssertTrue(fiveHour.isFiveHourSessionWindow)
        XCTAssertFalse(fiveHour.isWeeklyWindow)

        let weekly = try XCTUnwrap(snapshot.rateLimit(preferredID: "TOKENS_LIMIT-6"))
        XCTAssertTrue(weekly.isWeeklyWindow)
        XCTAssertFalse(weekly.isFiveHourSessionWindow)

        let tools = try XCTUnwrap(snapshot.rateLimit(preferredID: "TIME_LIMIT-5"))
        XCTAssertFalse(tools.isFiveHourSessionWindow)
        XCTAssertFalse(tools.isWeeklyWindow)
    }

    /// The live API now reports credit-based quotas ("CREDIT_LIMIT") instead
    /// of the token-based "TOKENS_LIMIT" the earlier integration targeted.
    /// `unit` is the stable window discriminator across both generations.
    func testParsesCreditLimitResponseAsSessionAndWeeklyWindows() throws {
        let creditLimits: [[String: Any]] = [
            [
                "type": "CREDIT_LIMIT",
                "unit": 3,
                "usage": 28_000.0,
                "currentValue": 6_859.0,
                "remaining": 21_141.0,
                "percentage": 24.51,
                "nextResetTime": 1_755_000_000_000
            ],
            [
                "type": "CREDIT_LIMIT",
                "unit": 6,
                "usage": 140_000.0,
                "currentValue": 7_440.0,
                "percentage": 5.31,
                "nextResetTime": 1_755_600_000_000
            ]
        ]
        let snapshot = try ZAIAPIService.parse(
            data: try encode(makeQuotaBody(level: "max", limits: creditLimits)),
            fetchedAt: Date()
        )

        XCTAssertEqual(snapshot.rateLimits.count, 2)
        XCTAssertEqual(snapshot.account?.planType, "max")

        let session = try XCTUnwrap(snapshot.rateLimits.first { $0.isFiveHourSessionWindow })
        XCTAssertEqual(session.primary?.windowDurationMinutes, 300)
        XCTAssertEqual(session.primary?.usedCredits, 6_859.0)
        XCTAssertEqual(session.primary?.totalCredits, 28_000.0)

        let weekly = try XCTUnwrap(snapshot.rateLimits.first { $0.isWeeklyWindow })
        XCTAssertEqual(weekly.primary?.windowDurationMinutes, 10_080)

        // The 5-hour credit window drives the tray icon and headline, even
        // though its id ("CREDIT_LIMIT-3") no longer matches the legacy
        // constant.
        XCTAssertEqual(snapshot.primaryRateLimit?.id, session.id)
    }

    func testClaudeAutoSwitchNeverSelectsZAIProvider() {
        let current = Profile(
            name: "Claude A",
            claudeSessionKey: "session-a",
            organizationId: "org-a"
        )
        let zaiProfile = Profile(name: "GLM", provider: .zai, zaiAPIKey: "key")
        let nextClaude = Profile(
            name: "Claude B",
            claudeSessionKey: "session-b",
            organizationId: "org-b"
        )

        let selected = MenuBarManager.nextClaudeAutoSwitchProfile(
            in: [current, zaiProfile, nextClaude],
            after: current.id
        )

        XCTAssertEqual(selected?.id, nextClaude.id)
    }

    func testSingleProfileProviderSwitchReassignsExistingStatusItem() {
        let transition = StatusBarMetricTransition.calculate(
            currentOrder: [.zai],
            newOrder: [.session]
        )
        XCTAssertEqual(transition.reassignments.count, 1)
        XCTAssertEqual(transition.reassignments.first?.from, .zai)
        XCTAssertEqual(transition.reassignments.first?.to, .session)
        XCTAssertTrue(transition.removals.isEmpty)
        XCTAssertTrue(transition.additions.isEmpty)
    }
}
