import XCTest
@testable import Claude_Usage

final class CodexUsageTests: XCTestCase {
    func testLiveAppServerWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_INTEGRATION_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_INTEGRATION_TEST=1 to exercise the signed-in local Codex CLI")
        }

        let snapshot = try await CodexAppServerService.shared.fetchUsage()
        XCTAssertNotNil(snapshot.primaryRateLimit)
        XCTAssertNotNil(snapshot.primaryRateLimit?.primary)
        CodexAppServerService.shared.stop()
    }

    func testParsesAppServerUsageSnapshot() throws {
        let account: [String: Any] = [
            "account": ["type": "chatgpt", "email": "user@example.com", "planType": "plus"]
        ]
        let limits: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "primary": [
                        "usedPercent": 42,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_000_000
                    ],
                    "credits": ["hasCredits": true, "unlimited": false, "balance": "12.5"],
                    "planType": "plus"
                ]
            ]
        ]
        let usage: [String: Any] = [
            "summary": ["lifetimeTokens": 123_456, "currentStreakDays": 3],
            "dailyUsageBuckets": [["startDate": "2026-07-21", "tokens": 1_234]]
        ]

        let snapshot = try CodexAppServerService.parseUsage(
            accountResult: account,
            rateLimitResult: limits,
            tokenUsageResult: usage
        )

        XCTAssertEqual(snapshot.account?.email, "user@example.com")
        XCTAssertEqual(snapshot.primaryRateLimit?.primary?.usedPercent, 42)
        XCTAssertEqual(snapshot.primaryRateLimit?.primary?.windowDurationMinutes, 10_080)
        XCTAssertEqual(snapshot.primaryRateLimit?.credits?.balance, "12.5")
        XCTAssertEqual(snapshot.tokenUsage?.lifetimeTokens, 123_456)
        XCTAssertEqual(snapshot.tokenUsage?.dailyBuckets.first?.tokens, 1_234)
    }

    func testLegacyMenuBarConfigurationGainsDisabledCodexMetric() throws {
        let original = MenuBarIconConfiguration.default
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var metrics = try XCTUnwrap(json["metrics"] as? [[String: Any]])
        metrics.removeAll { $0["metricType"] as? String == MenuBarMetricType.codex.rawValue }
        json["metrics"] = metrics

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(MenuBarIconConfiguration.self, from: legacyData)

        let codex = try XCTUnwrap(decoded.config(for: .codex))
        XCTAssertFalse(codex.isEnabled)
        XCTAssertEqual(codex.order, 3)
    }

    func testCodexUsageRoundTripsThroughCodable() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let original = CodexUsage(
            account: CodexAccount(email: nil, planType: "business"),
            rateLimits: [
                CodexRateLimit(
                    id: "codex",
                    name: nil,
                    primary: CodexRateLimitWindow(
                        usedPercent: 7,
                        windowDurationMinutes: 300,
                        resetsAt: reset
                    ),
                    secondary: nil,
                    credits: nil,
                    planType: "business",
                    reachedType: nil
                )
            ],
            tokenUsage: nil,
            lastUpdated: reset
        )

        let decoded = try JSONDecoder().decode(CodexUsage.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testPreferredRateLimitFallsBackToGeneralCodexBucket() {
        let snapshot = CodexUsage(
            account: nil,
            rateLimits: [
                CodexRateLimit(id: "codex", name: "General", primary: nil, secondary: nil, credits: nil, planType: nil, reachedType: nil),
                CodexRateLimit(id: "model", name: "Model", primary: nil, secondary: nil, credits: nil, planType: nil, reachedType: nil)
            ],
            tokenUsage: nil,
            lastUpdated: Date()
        )

        XCTAssertEqual(snapshot.rateLimit(preferredID: "model")?.id, "model")
        XCTAssertEqual(snapshot.rateLimit(preferredID: "missing")?.id, "codex")
        XCTAssertEqual(snapshot.rateLimit(preferredID: nil)?.id, "codex")
    }

    func testCodexSettingsMigratesLegacyProfileMetric() {
        var legacy = MetricIconConfig.codexDefault
        legacy.isEnabled = true
        legacy.iconStyle = .compact

        let migrated = CodexSettings.migratingLegacyMetric(legacy)

        XCTAssertTrue(migrated.monitoringEnabled)
        XCTAssertTrue(migrated.menuBarMetric.isEnabled)
        XCTAssertEqual(migrated.menuBarMetric.iconStyle, .compact)
        XCTAssertEqual(migrated.menuBarMetric.metricType, .codex)
        XCTAssertFalse(migrated.notificationsEnabled)
    }

    func testCodexSettingsBackwardCompatibleDefaults() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "monitoringEnabled": false,
            "notificationThresholds": [95, 75, 75, 0, 101]
        ])

        let decoded = try JSONDecoder().decode(CodexSettings.self, from: data)

        XCTAssertFalse(decoded.monitoringEnabled)
        XCTAssertEqual(decoded.notificationThresholds, [75, 95])
        XCTAssertEqual(decoded.menuBarMetric.metricType, .codex)
        XCTAssertTrue(decoded.showAccountEmail)
    }

    func testCustomExecutablePathTakesPriority() {
        XCTAssertEqual(
            CodexAppServerService.resolveExecutable(customExecutablePath: "/bin/sh")?.path,
            "/bin/sh"
        )
    }
}
