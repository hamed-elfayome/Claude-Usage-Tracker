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

    func testRejectsUnrecognizedRateLimitResponseWithoutReplacingCachedUsage() {
        XCTAssertThrowsError(
            try CodexAppServerService.parseUsage(
                accountResult: [:],
                rateLimitResult: ["renamedLimits": [:]],
                tokenUsageResult: [:]
            )
        ) { error in
            guard case CodexAppServerError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testRejectsNonemptyMalformedRateLimitBuckets() {
        XCTAssertThrowsError(
            try CodexAppServerService.parseUsage(
                accountResult: [:],
                rateLimitResult: [
                    "rateLimitsByLimitId": [
                        "codex": ["limitId": "codex", "primary": ["renamedPercent": 42]]
                    ]
                ],
                tokenUsageResult: [:]
            )
        ) { error in
            guard case CodexAppServerError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testAcceptsRecognizedEmptyRateLimitResponse() throws {
        let snapshot = try CodexAppServerService.parseUsage(
            accountResult: [:],
            rateLimitResult: ["rateLimitsByLimitId": [:]],
            tokenUsageResult: [:]
        )

        XCTAssertTrue(snapshot.rateLimits.isEmpty)
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

    func testCodexProfileRoundTripsProviderConnectionAndUsage() throws {
        let usage = CodexUsage(
            account: CodexAccount(email: "codex@example.com", planType: "pro"),
            rateLimits: [],
            tokenUsage: nil,
            lastUpdated: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let profile = Profile(
            name: "Remote Codex",
            provider: .codex,
            codexUsage: usage,
            codexConfiguration: CodexProfileConfiguration(
                connectionType: .ssh,
                executablePath: "/opt/homebrew/bin/codex",
                codexHome: "/srv/codex-work",
                sshHost: "codex-vm",
                selectedRateLimitID: "codex",
                showAccountEmail: false
            ),
            iconConfig: .codexProfileDefault
        )

        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))

        XCTAssertEqual(decoded.provider, .codex)
        XCTAssertEqual(decoded.codexConfiguration.connectionType, .ssh)
        XCTAssertEqual(decoded.codexConfiguration.sshHost, "codex-vm")
        XCTAssertEqual(decoded.codexConfiguration.codexHome, "/srv/codex-work")
        XCTAssertEqual(decoded.codexUsage, usage)
        XCTAssertTrue(decoded.iconConfig.config(for: .codex)?.isEnabled == true)
        XCTAssertFalse(decoded.iconConfig.config(for: .session)?.isEnabled == true)
    }

    func testLegacyProfileDefaultsToClaudeProvider() throws {
        let profile = Profile(name: "Legacy")
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        json.removeValue(forKey: "provider")
        json.removeValue(forKey: "codexConfiguration")
        let decoded = try JSONDecoder().decode(
            Profile.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertEqual(decoded.provider, .claude)
        XCTAssertNil(decoded.codexUsage)
    }

    func testSSHConfigurationRequiresSafeHostAlias() {
        XCTAssertNotNil(
            CodexProfileConfiguration(connectionType: .ssh).validationError
        )
        XCTAssertNotNil(
            CodexProfileConfiguration(connectionType: .ssh, sshHost: "-oProxyCommand=bad")
                .validationError
        )
        XCTAssertNil(
            CodexProfileConfiguration(connectionType: .ssh, sshHost: "codex-vm")
                .validationError
        )
    }

    func testCustomExecutablePathTakesPriority() {
        XCTAssertEqual(
            CodexAppServerService.resolveExecutable(customExecutablePath: "/bin/sh")?.path,
            "/bin/sh"
        )
    }

    func testInvalidCustomExecutableDoesNotFallBackToAnotherInstallation() {
        XCTAssertNil(
            CodexAppServerService.resolveExecutable(
                customExecutablePath: "/definitely/not/a/codex/executable"
            )
        )
    }

    func testAppServerTimeoutStopsTransportAndNextRefreshRestarts() async throws {
        let factory = FakeCodexTransportFactory(responseModes: [.silent, .automatic])
        let service = CodexAppServerService(
            requestTimeout: 0.05,
            transportFactory: factory.makeTransport
        )
        let configuration = CodexProfileConfiguration(executablePath: "/bin/sh")

        do {
            _ = try await service.fetchUsage(configuration: configuration)
            XCTFail("Expected the silent app-server transport to time out")
        } catch {
            guard case CodexAppServerError.timedOut("initialize") = error else {
                return XCTFail("Expected initialize timeout, got \(error)")
            }
        }

        let timedOutTransport = try XCTUnwrap(factory.transport(at: 0))
        XCTAssertEqual(timedOutTransport.stopCount, 1)
        XCTAssertFalse(timedOutTransport.isRunning)

        let usage = try await service.fetchUsage(configuration: configuration)

        XCTAssertEqual(usage.primaryRateLimit?.primary?.usedPercent, 12)
        XCTAssertEqual(factory.transportCount, 2)
        service.stop()
    }

    func testStaleTransportTerminationDoesNotStopReplacement() async throws {
        let factory = FakeCodexTransportFactory(responseModes: [.automatic, .automatic])
        let service = CodexAppServerService(
            requestTimeout: 1,
            transportFactory: factory.makeTransport
        )
        let firstConfiguration = CodexProfileConfiguration(executablePath: "/bin/sh")
        let secondConfiguration = CodexProfileConfiguration(
            executablePath: "/bin/sh",
            codexHome: "/tmp/codex-app-server-tests-account-2"
        )

        _ = try await service.fetchUsage(configuration: firstConfiguration)
        let firstTransport = try XCTUnwrap(factory.transport(at: 0))
        let staleTermination = try XCTUnwrap(firstTransport.onTermination)

        _ = try await service.fetchUsage(configuration: secondConfiguration)
        let replacementTransport = try XCTUnwrap(factory.transport(at: 1))
        XCTAssertEqual(firstTransport.stopCount, 1)
        XCTAssertEqual(replacementTransport.stopCount, 0)

        staleTermination()
        let usage = try await service.fetchUsage(configuration: secondConfiguration)

        XCTAssertEqual(usage.primaryRateLimit?.primary?.usedPercent, 12)
        XCTAssertEqual(factory.transportCount, 2)
        XCTAssertEqual(replacementTransport.stopCount, 0)
        service.stop()
    }

    func testConnectionIdentityIgnoresPresentationSettings() {
        let original = CodexProfileConfiguration(
            connectionType: .ssh,
            executablePath: "/usr/local/bin/codex",
            codexHome: "/srv/account-a",
            sshHost: "codex-vm",
            selectedRateLimitID: "codex",
            showAccountEmail: true
        )
        var presentationOnly = original
        presentationOnly.selectedRateLimitID = "model"
        presentationOnly.showAccountEmail = false

        XCTAssertTrue(original.targetsSameInstallation(as: presentationOnly))

        var anotherAccount = original
        anotherAccount.codexHome = "/srv/account-b"
        XCTAssertFalse(original.targetsSameInstallation(as: anotherAccount))
    }

    func testClaudeAutoSwitchNeverSelectsCodexProvider() {
        let current = Profile(
            name: "Claude A",
            claudeSessionKey: "session-a",
            organizationId: "org-a"
        )
        let codex = Profile(
            name: "Codex",
            provider: .codex,
            codexConfiguration: CodexProfileConfiguration()
        )
        let nextClaude = Profile(
            name: "Claude B",
            claudeSessionKey: "session-b",
            organizationId: "org-b"
        )

        let selected = MenuBarManager.nextClaudeAutoSwitchProfile(
            in: [current, codex, nextClaude],
            after: current.id
        )

        XCTAssertEqual(selected?.id, nextClaude.id)
    }

    func testSingleProfileProviderSwitchReassignsExistingStatusItem() {
        let toCodex = StatusBarMetricTransition.calculate(
            currentOrder: [.session],
            newOrder: [.codex]
        )

        XCTAssertEqual(
            toCodex.reassignments,
            [.init(from: .session, to: .codex)]
        )
        XCTAssertTrue(toCodex.removals.isEmpty)
        XCTAssertTrue(toCodex.additions.isEmpty)

        let backToClaude = StatusBarMetricTransition.calculate(
            currentOrder: [.codex],
            newOrder: [.session]
        )

        XCTAssertEqual(
            backToClaude.reassignments,
            [.init(from: .codex, to: .session)]
        )
        XCTAssertTrue(backToClaude.removals.isEmpty)
        XCTAssertTrue(backToClaude.additions.isEmpty)
    }

    func testOpenAIStatusFeedDetectsActiveGenericIncidentAffectingCodex() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title type="html"><![CDATA[Elevated Error Rates]]></title>
            <id>https://status.openai.com/incidents/incident-1</id>
            <summary type="html"><![CDATA[
              <b>Status: Monitoring</b><br/><br/>
              We are monitoring the recovery.<br/><br/>
              <b>Affected components</b>
              <ul>
                <li>Codex API (Operational)</li>
                <li>CLI (Operational)</li>
              </ul>
            ]]></summary>
          </entry>
        </feed>
        """
        let summary = """
        {
          "incidents": [
            {
              "id": "incident-1",
              "status": "monitoring",
              "impact": "minor"
            }
          ]
        }
        """

        let incidents = try OpenAIStatusFeedParser.parse(try XCTUnwrap(feed.data(using: .utf8)))
        let status = OpenAIStatusService.status(
            from: incidents,
            summaryData: try XCTUnwrap(summary.data(using: .utf8))
        )

        XCTAssertEqual(incidents.first?.affectedComponents, ["Codex API", "CLI"])
        XCTAssertEqual(status.indicator, .minor)
        XCTAssertEqual(status.description, "Elevated Error Rates · Monitoring")
    }

    func testOpenAIStatusFeedIgnoresResolvedAndNonCodexIncidents() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title><![CDATA[Past Codex issue]]></title>
            <id>https://status.openai.com/incidents/resolved</id>
            <summary type="html"><![CDATA[
              <b>Status: Resolved</b>
              <ul><li>Codex Web (Operational)</li></ul>
            ]]></summary>
          </entry>
          <entry>
            <title><![CDATA[Current image issue]]></title>
            <id>https://status.openai.com/incidents/images</id>
            <summary type="html"><![CDATA[
              <b>Status: Investigating</b>
              <ul><li>Images (Degraded performance)</li></ul>
            ]]></summary>
          </entry>
        </feed>
        """

        let incidents = try OpenAIStatusFeedParser.parse(try XCTUnwrap(feed.data(using: .utf8)))
        let status = OpenAIStatusService.status(from: incidents, summaryData: nil)

        XCTAssertEqual(status.indicator, .none)
        XCTAssertEqual(status.description, "All Codex systems operational")
    }

    func testOpenAIStatusUsesSummaryImpactSeverity() {
        let incident = OpenAIStatusFeedIncident(
            id: "major-codex",
            title: "Codex unavailable",
            status: "identified",
            affectedComponents: ["VS Code extension"]
        )
        let summary = """
        {
          "incidents": [
            {
              "id": "major-codex",
              "status": "identified",
              "impact": "major"
            }
          ]
        }
        """

        let status = OpenAIStatusService.status(
            from: [incident],
            summaryData: summary.data(using: .utf8)
        )

        XCTAssertEqual(status.indicator, .major)
        XCTAssertEqual(status.description, "Codex unavailable · Identified")
    }

    func testOpenAISummaryWithNoIncidentsIsAuthoritativeWhenFeedFails() throws {
        let summary = try XCTUnwrap(#"{"incidents":[]}"#.data(using: .utf8))

        let status = OpenAIStatusService.status(feedData: nil, summaryData: summary)

        XCTAssertEqual(status?.indicator, ClaudeStatus.StatusIndicator.none)
        XCTAssertEqual(status?.description, "All Codex systems operational")
    }

    func testOpenAIStatusDoesNotReturnGreenWhenSummaryIncidentIsMissingFromFeed() throws {
        let resolvedFeed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Past image incident</title>
            <id>https://status.openai.com/incidents/resolved-image</id>
            <summary type="html"><![CDATA[
              <b>Status: Resolved</b>
              <ul><li>Images (Operational)</li></ul>
            ]]></summary>
          </entry>
        </feed>
        """
        let summary = """
        {
          "incidents": [
            {
              "id": "current-unknown",
              "name": "Elevated Error Rates",
              "status": "monitoring",
              "impact": "minor"
            }
          ]
        }
        """

        let status = OpenAIStatusService.status(
            feedData: try XCTUnwrap(resolvedFeed.data(using: .utf8)),
            summaryData: try XCTUnwrap(summary.data(using: .utf8))
        )

        XCTAssertEqual(status?.indicator, .unknown)
        XCTAssertEqual(status?.description, "Elevated Error Rates · Monitoring")
    }

    func testOpenAIStatusDoesNotReturnGreenForGenericMatchedIncidentWithoutComponents() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Elevated Error Rates</title>
            <id>https://status.openai.com/incidents/current-unknown</id>
            <summary type="html"><![CDATA[
              <strong>Status: Monitoring</strong>
              We are monitoring recovery.
            ]]></summary>
          </entry>
        </feed>
        """
        let summary = """
        {
          "incidents": [
            {
              "id": "current-unknown",
              "name": "Elevated Error Rates",
              "status": "monitoring",
              "impact": "minor"
            }
          ]
        }
        """

        let status = OpenAIStatusService.status(
            feedData: try XCTUnwrap(feed.data(using: .utf8)),
            summaryData: try XCTUnwrap(summary.data(using: .utf8))
        )

        XCTAssertEqual(status?.indicator, .unknown)
        XCTAssertEqual(status?.description, "Elevated Error Rates · Monitoring")
    }

    func testOpenAIStatusDoesNotReturnGreenWhenFeedIsResolvedButSummaryIsActive() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Elevated Error Rates</title>
            <id>https://status.openai.com/incidents/disputed</id>
            <summary type="html"><![CDATA[
              <strong>Status: Resolved</strong>
              <ul><li>Codex API (Operational)</li></ul>
            ]]></summary>
          </entry>
        </feed>
        """
        let summary = """
        {
          "incidents": [
            {
              "id": "disputed",
              "name": "Elevated Error Rates",
              "status": "monitoring",
              "impact": "minor"
            }
          ]
        }
        """

        let status = OpenAIStatusService.status(
            feedData: try XCTUnwrap(feed.data(using: .utf8)),
            summaryData: try XCTUnwrap(summary.data(using: .utf8))
        )

        XCTAssertEqual(status?.indicator, .unknown)
        XCTAssertEqual(status?.description, "Elevated Error Rates · Monitoring")
    }

    func testOperationalComponentsFallbackIsUnknown() throws {
        let components = try XCTUnwrap(
            #"{"components":[{"name":"Codex API","status":"operational"}]}"#
                .data(using: .utf8)
        )

        let status = try OpenAIStatusService.statusFromComponents(components)

        XCTAssertEqual(status.indicator, .unknown)
    }

    func testOpenAIStatusFeedParsesInlineAffectedComponents() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Elevated Error Rates</title>
            <id>https://status.openai.com/incidents/current-codex</id>
            <summary type="html"><![CDATA[
              <strong>Status: Monitoring</strong>
              Affected components: Codex API; CLI
            ]]></summary>
          </entry>
        </feed>
        """

        let incidents = try OpenAIStatusFeedParser.parse(
            try XCTUnwrap(feed.data(using: .utf8))
        )

        XCTAssertEqual(incidents.first?.affectedComponents, ["Codex API", "CLI"])
        XCTAssertTrue(try XCTUnwrap(incidents.first).affectsCodex)
    }

    func testOpenAIStatusFeedRejectsPartiallyParsedEntries() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Past Codex issue</title>
            <id>https://status.openai.com/incidents/resolved</id>
            <summary type="html"><![CDATA[
              <b>Status: Resolved</b>
              <ul><li>Codex Web (Operational)</li></ul>
            ]]></summary>
          </entry>
          <entry>
            <title>Current Codex issue</title>
            <id>https://status.openai.com/incidents/current</id>
            <summary type="html"><![CDATA[
              <em>Lifecycle: Monitoring</em>
              <ul><li>Codex API (Degraded performance)</li></ul>
            ]]></summary>
          </entry>
        </feed>
        """

        XCTAssertThrowsError(
            try OpenAIStatusFeedParser.parse(try XCTUnwrap(feed.data(using: .utf8)))
        )
    }

    func testOpenAIStatusFeedSupportsStrongContentMarkup() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Elevated Error Rates</title>
            <id>https://status.openai.com/incidents/current</id>
            <content type="html"><![CDATA[
              <strong>Status:</strong> Monitoring
              <ul><li><span>Codex API</span> (Degraded performance)</li></ul>
            ]]></content>
          </entry>
        </feed>
        """

        let incidents = try OpenAIStatusFeedParser.parse(
            try XCTUnwrap(feed.data(using: .utf8))
        )

        XCTAssertEqual(incidents.first?.status, "Monitoring")
        XCTAssertEqual(incidents.first?.affectedComponents, ["Codex API"])
        XCTAssertTrue(incidents.first?.affectsCodex == true)
    }
}

private final class FakeCodexTransportFactory: @unchecked Sendable {
    enum ResponseMode: Equatable {
        case silent
        case automatic
    }

    private let lock = NSLock()
    private var responseModes: [ResponseMode]
    private var transports: [FakeCodexAppServerTransport] = []

    init(responseModes: [ResponseMode]) {
        self.responseModes = responseModes
    }

    var transportCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return transports.count
    }

    func transport(at index: Int) -> FakeCodexAppServerTransport? {
        lock.lock()
        defer { lock.unlock() }
        guard transports.indices.contains(index) else { return nil }
        return transports[index]
    }

    func makeTransport() -> CodexAppServerTransport {
        lock.lock()
        defer { lock.unlock() }
        let mode = responseModes.isEmpty ? .automatic : responseModes.removeFirst()
        let transport = FakeCodexAppServerTransport(responseMode: mode)
        transports.append(transport)
        return transport
    }
}

private final class FakeCodexAppServerTransport: CodexAppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let responseMode: FakeCodexTransportFactory.ResponseMode
    private var running = false
    private var recordedStopCount = 0

    var onStdout: ((Data) -> Void)?
    var onStderr: ((Data) -> Void)?
    var onTermination: (() -> Void)?

    init(responseMode: FakeCodexTransportFactory.ResponseMode) {
        self.responseMode = responseMode
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedStopCount
    }

    func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) throws {
        lock.lock()
        running = true
        lock.unlock()
    }

    func send(_ data: Data) throws {
        guard isRunning else {
            throw CodexAppServerError.processTerminated
        }
        guard responseMode == .automatic,
              let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestID = (request["id"] as? NSNumber)?.intValue,
              let method = request["method"] as? String else {
            return
        }

        let result: [String: Any]
        switch method {
        case "account/read":
            result = ["account": ["planType": "plus"]]
        case "account/rateLimits/read":
            result = [
                "rateLimitsByLimitId": [
                    "codex": [
                        "limitId": "codex",
                        "primary": [
                            "usedPercent": 12,
                            "windowDurationMins": 300
                        ]
                    ]
                ]
            ]
        default:
            result = [:]
        }

        var response = try JSONSerialization.data(
            withJSONObject: ["id": requestID, "result": result]
        )
        response.append(0x0A)
        onStdout?(response)
    }

    func stop() {
        lock.lock()
        running = false
        recordedStopCount += 1
        lock.unlock()
    }
}
