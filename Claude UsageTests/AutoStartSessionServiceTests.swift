import Foundation
import XCTest
@testable import Claude_Usage

@MainActor
final class AutoStartSessionServiceTests: XCTestCase {
    private var fixture: AutoStartHTTPFixture!
    private var session: URLSession!
    private var errors: [String] = []
    private var notifications: [Bool] = []

    override func setUp() async throws {
        fixture = AutoStartHTTPFixture()
        AutoStartStubURLProtocol.setHandler { [fixture = fixture!] request in
            try fixture.respond(to: request)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoStartStubURLProtocol.self]
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        errors = []
        notifications = []
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        AutoStartStubURLProtocol.setHandler(nil)
        session = nil
        fixture = nil
    }

    func test_autoStartDoesNotCreateConversation_whenWeeklyExhaustedAndExtraCreditsOff() async {
        // Regression: a fresh five-hour window does not restore an exhausted weekly allowance.
        fixture.configure {
            $0.weeklyPercentage = 100
            $0.extraUsageBody = #"{"is_enabled":false}"#
            $0.sessionPercentage = 0
            $0.sessionResetTime = nil
        }
        let service = makeService()

        await service.checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 0)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/completion"), 0)
    }

    func test_repeatedChecksDoNotCreateConversations_whenWeeklyExhausted() async {
        let service = makeService()

        for _ in 0..<3 {
            await service.checkAllProfiles(source: "test")
        }

        assertNoInitialization()
        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/usage"), 3)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(notifications.isEmpty)
    }

    func test_autoStartResumes_whenFreshWeeklyUsageConfirmsReset() async {
        let service = makeService()
        await service.checkAllProfiles(source: "test")
        await service.checkAllProfiles(source: "test")
        assertNoInitialization()

        fixture.configure { $0.weeklyPercentage = 0 }
        await service.checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/usage"), 3)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 1)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/completion"), 1)
        XCTAssertEqual(notifications, [true])
        XCTAssertTrue(errors.isEmpty)
    }

    func test_autoStartRemainsBlocked_whenResetDatePassesButWeeklyUsageIsStillFull() async {
        fixture.configure { $0.weeklyResetTime = "2020-01-01T00:00:00.000Z" }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
    }

    func test_autoStartAllowed_whenWeeklyUsageExceeds100AndExtraCreditsExplicitlyEnabled() async {
        fixture.configure {
            $0.weeklyPercentage = 101
            $0.extraUsageBody = #"{"is_enabled":true}"#
        }

        await makeService(checkOverageLimitEnabled: false).checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/overage_spend_limit"), 1)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 1)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/completion"), 1)
    }

    func test_extraUsageDisplayDisabledDoesNotBypassWeeklyGuard() async {
        await makeService(checkOverageLimitEnabled: false).checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/overage_spend_limit"), 1)
    }

    func test_availableWeeklyAllowanceDoesNotRequireExtraCreditsRequest() async {
        fixture.configure {
            $0.weeklyPercentage = 99.9
            $0.failingPathSuffix = "/overage_spend_limit"
        }

        await makeService().checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/overage_spend_limit"), 0)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_fullFiveHourSessionDoesNotAutoStart() async {
        fixture.configure { $0.sessionPercentage = 100 }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/overage_spend_limit"), 0)
    }

    func test_openFiveHourWindowAtZeroDoesNotAutoStart() async {
        fixture.configure { $0.sessionResetTime = "2099-01-01T00:00:00.000Z" }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/overage_spend_limit"), 0)
    }

    func test_expiredFiveHourWindowDoesNotBypassWeeklyGuard() async {
        fixture.configure {
            $0.sessionPercentage = 100
            $0.sessionResetTime = "2020-01-01T00:00:00.000Z"
        }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
    }

    func test_disabledAutoStartDoesNotFetchOrInitialize() async {
        await makeService(autoStartEnabled: false).checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "GET", suffix: "/usage"), 0)
        assertNoInitialization()
    }

    func test_unknownExtraCreditPermissionPreventsAutoStartAndLogsReason() async {
        let bodies = ["{}", #"{"is_enabled":null}"#, #"{"is_enabled":"true"}"#, "not JSON"]
        for body in bodies {
            fixture.configure { $0.extraUsageBody = body }
            await makeService().checkAllProfiles(source: "test")
        }

        assertNoInitialization()
        XCTAssertEqual(errors.count, 4)
        XCTAssertTrue(errors.allSatisfy {
            $0.lowercased().contains("extra usage permission")
        })
        XCTAssertTrue(notifications.isEmpty)
    }

    func test_extraCreditHTTPFailurePreventsAutoStartAndLogsReason() async {
        fixture.configure { $0.extraUsageStatus = 503 }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("extra usage permission") == true)
    }

    func test_extraCreditTransportFailurePreventsAutoStartAndLogsReason() async {
        fixture.configure { $0.failingPathSuffix = "/overage_spend_limit" }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("Weekly regression fixture") == true)
        XCTAssertTrue(notifications.isEmpty)
    }

    func test_missingWeeklyUsageDoesNotBecomeAnAvailableAllowance() async {
        fixture.configure { $0.weeklyPercentage = nil }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(errors.count, 1)
    }

    func test_invalidWeeklyUsageDoesNotBecomeAnAvailableAllowance() async {
        fixture.configure { $0.weeklyPercentage = "unavailable" }

        await makeService().checkAllProfiles(source: "test")

        assertNoInitialization()
        XCTAssertEqual(errors.count, 1)
    }

    func test_failedInitializationDeletesTemporaryConversation() async {
        fixture.configure {
            $0.weeklyPercentage = 0
            $0.completionStatus = 429
        }

        await makeService().checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 1)
        XCTAssertEqual(fixture.requestCount(method: "DELETE", suffix: "/fixture-conversation"), 1)
        XCTAssertEqual(notifications, [false])
        XCTAssertEqual(errors.count, 1)
    }

    func test_initializationTransportFailureDeletesTemporaryConversation() async {
        fixture.configure {
            $0.weeklyPercentage = 0
            $0.failingPathSuffix = "/completion"
        }

        await makeService().checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "DELETE", suffix: "/fixture-conversation"), 1)
        XCTAssertEqual(notifications, [false])
        XCTAssertEqual(errors.count, 1)
    }

    func test_cleanupHTTPFailureIsLoggedWithoutHidingInitializationFailure() async {
        fixture.configure {
            $0.weeklyPercentage = 0
            $0.completionStatus = 429
            $0.deleteStatus = 503
        }

        await makeService().checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "DELETE", suffix: "/fixture-conversation"), 1)
        XCTAssertEqual(notifications, [false])
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.contains { $0.contains("429") })
        XCTAssertTrue(errors.contains { $0.contains("503") })
    }

    func test_cleanupFailureDoesNotMisreportASuccessfullyStartedSession() async {
        fixture.configure {
            $0.weeklyPercentage = 0
            $0.deleteStatus = 503
        }

        await makeService().checkAllProfiles(source: "test")

        XCTAssertEqual(fixture.requestCount(method: "DELETE", suffix: "/fixture-conversation"), 1)
        XCTAssertEqual(notifications, [true])
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains("503") == true)
    }

    private func assertNoInitialization(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/chat_conversations"), 0, file: file, line: line)
        XCTAssertEqual(fixture.requestCount(method: "POST", suffix: "/completion"), 0, file: file, line: line)
    }

    private func makeService(
        autoStartEnabled: Bool = true,
        checkOverageLimitEnabled: Bool = true
    ) -> AutoStartSessionService {
        let profile = Profile(
            name: "Weekly regression fixture",
            claudeSessionKey: "fake-session-key",
            organizationId: "fixture-org",
            autoStartSessionEnabled: autoStartEnabled,
            checkOverageLimitEnabled: checkOverageLimitEnabled
        )
        return AutoStartSessionService(
            session: session,
            profiles: { [profile] },
            saveUsage: { _, _ in },
            notify: { [weak self] _, success, _ in self?.notifications.append(success) },
            logError: { [weak self] in self?.errors.append($0) }
        )
    }
}

/// Replaces HTTP transport only: parsing, eligibility, creation, completion, and
/// deletion still run through the production AutoStartSessionService.
private final class AutoStartHTTPFixture {
    struct Settings {
        var weeklyPercentage: Any? = 100
        var sessionPercentage = 0.0
        var sessionResetTime: String?
        var weeklyResetTime = "2099-01-01T00:00:00.000Z"
        var extraUsageBody = #"{"is_enabled":false}"#
        var extraUsageStatus = 200
        var completionStatus = 200
        var completionBody = "data: {\"messageLimit\":{\"windows\":{\"5h\":{\"resets_at\":4070908800}}}}\n"
        var deleteStatus = 204
        var failingPathSuffix: String?
    }

    private let lock = NSLock()
    private var settings = Settings()
    private var requests: [URLRequest] = []

    func configure(_ update: (inout Settings) -> Void) {
        lock.withLock { update(&settings) }
    }

    func requestCount(method: String, suffix: String) -> Int {
        lock.withLock {
            requests.filter { $0.httpMethod == method && $0.url?.path.hasSuffix(suffix) == true }.count
        }
    }

    func respond(to request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            requests.append(request)
            let path = request.url?.path ?? ""
            if let suffix = settings.failingPathSuffix, path.hasSuffix(suffix) {
                throw URLError(.timedOut)
            }
            switch (request.httpMethod, path) {
            case ("GET", _) where path.hasSuffix("/usage"):
                return (200, try usageData())
            case ("GET", _) where path.hasSuffix("/overage_spend_limit"):
                return (settings.extraUsageStatus, Data(settings.extraUsageBody.utf8))
            case ("POST", _) where path.hasSuffix("/chat_conversations"):
                return (201, Data(#"{"uuid":"fixture-conversation"}"#.utf8))
            case ("POST", _) where path.hasSuffix("/completion"):
                return (settings.completionStatus, Data(settings.completionBody.utf8))
            case ("DELETE", _) where path.hasSuffix("/fixture-conversation"):
                return (settings.deleteStatus, Data())
            default:
                throw URLError(.unsupportedURL)
            }
        }
    }

    private func usageData() throws -> Data {
        let json: [String: Any] = [
            "five_hour": [
                "utilization": settings.sessionPercentage,
                "resets_at": settings.sessionResetTime as Any? ?? NSNull()
            ],
            "seven_day": [
                "utilization": settings.weeklyPercentage ?? NSNull(),
                "resets_at": settings.weeklyResetTime
            ],
            "seven_day_opus": ["utilization": 0],
            "seven_day_sonnet": ["utilization": 0]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }
}

private final class AutoStartStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, Data))?

    static func setHandler(_ handler: ((URLRequest) throws -> (Int, Data))?) {
        lock.withLock { self.handler = handler }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.lock.withLock({ Self.handler }),
                  let url = request.url else {
                throw URLError(.unsupportedURL)
            }
            let (status, data) = try handler(request)
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            ) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
