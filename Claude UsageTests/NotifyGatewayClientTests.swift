import XCTest
@testable import Claude_Usage

/// The wire: how a status code becomes an error with a remedy, what goes into a
/// body, and how a URL is built around a secret.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyGatewayClientTests: XCTestCase {

    private func body(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    // MARK: - Status mapping

    func testEachStatusMapsToTheErrorWhoseRemedyDiffers() {
        XCTAssertEqual(
            NotifyGatewayClient.failure(status: 403, data: Data(), retryAfterHeader: nil),
            .rejectedCredentials
        )
        XCTAssertEqual(
            NotifyGatewayClient.failure(status: 410, data: Data(), retryAfterHeader: nil),
            .tileGone
        )
        XCTAssertEqual(
            NotifyGatewayClient.failure(status: 418, data: Data(), retryAfterHeader: nil),
            .unexpectedStatus(418)
        )
    }

    func testA400CarriesTheGatewaysOwnSentence() {
        let error = NotifyGatewayClient.failure(
            status: 400,
            data: body(["message": "title is too long"]),
            retryAfterHeader: nil
        )
        XCTAssertEqual(error, .invalidPayload("title is too long"))
    }

    func testA409NamesWhatTheDeviceIsWaitingOn() {
        let error = NotifyGatewayClient.failure(
            status: 409,
            data: body(["message": "open the Notify! app once"]),
            retryAfterHeader: nil
        )
        XCTAssertEqual(error, .liveActivityUnavailable("open the Notify! app once"))
    }

    func testA429BecomesAWait() {
        let error = NotifyGatewayClient.failure(
            status: 429,
            data: body(["retryAfterSeconds": 120, "openingTheAppMayHelp": true]),
            retryAfterHeader: nil
        )
        XCTAssertEqual(error, .backoff(retryAfter: 120, openingTheAppMayHelp: true))
    }

    /// Apple never answered, so a tile may exist. The id is kept and polled
    /// rather than started again, which could leave two tiles.
    func testA502UnknownKeepsTheActivityId() {
        let error = NotifyGatewayClient.failure(
            status: 502,
            data: body(["deliveryState": "unknown", "activityId": "LA123456"]),
            retryAfterHeader: nil
        )
        XCTAssertEqual(error, .deliveryUnconfirmed(activityId: "LA123456"))
    }

    /// No tile exists, so starting again is safe, but every unanswered start
    /// counts toward the same ladder as a 429, so this is a wait.
    func testA502NotDeliveredBecomesAWait() {
        let error = NotifyGatewayClient.failure(
            status: 502,
            data: body(["deliveryState": "not-delivered"]),
            retryAfterHeader: nil
        )
        XCTAssertEqual(
            error,
            .backoff(retryAfter: NotifyGatewayClient.defaultBackoff, openingTheAppMayHelp: false)
        )
    }

    func testA502WithNoDeliveryStateIsJustAStatus() {
        XCTAssertEqual(
            NotifyGatewayClient.failure(status: 502, data: Data(), retryAfterHeader: nil),
            .unexpectedStatus(502)
        )
    }

    // MARK: - Wait resolution

    /// The body's own number wins, because the gateway computes it from the
    /// ladder it is actually enforcing.
    func testTheBodysSecondsBeatTheHeader() {
        XCTAssertEqual(NotifyGatewayClient.retryAfter(bodySeconds: 90, header: "300"), 90)
    }

    func testTheHeaderIsTheFallback() {
        XCTAssertEqual(NotifyGatewayClient.retryAfter(bodySeconds: nil, header: " 300 "), 300)
    }

    /// The HTTP date form is deliberately not read: it would need a clock this
    /// app cannot trust to agree with the server's.
    func testANonNumericHeaderFallsThroughToTheLaddersFirstRung() {
        XCTAssertEqual(
            NotifyGatewayClient.retryAfter(bodySeconds: nil, header: "Wed, 21 Oct 2026 07:28:00 GMT"),
            NotifyGatewayClient.defaultBackoff
        )
        XCTAssertEqual(
            NotifyGatewayClient.retryAfter(bodySeconds: nil, header: nil),
            NotifyGatewayClient.defaultBackoff
        )
    }

    // MARK: - Bodies

    /// Every field this app drives is present on every write, as an explicit
    /// null when it has no value. The gateway merges rather than replaces, so
    /// omitting a field it already holds freezes the old value instead of
    /// clearing it.
    func testTheTileBodyStatesANullForEveryFieldItDrives() {
        let tile = NotifyTile(title: "Claude Usage")!
        let body = NotifyGatewayClient.tileBody(tile)

        XCTAssertEqual(body["title"] as? String, "Claude Usage")
        for key in ["body", "symbol", "tint", "progress", "trailing", "metrics"] {
            XCTAssertTrue(body[key] is NSNull, "\(key) should be an explicit null")
        }
    }

    /// The fields this app never drives stay unmentioned, which is what lets an
    /// update from here share a tile with whatever else the user set up.
    func testTheTileBodyNeverMentionsTheFieldsItDoesNotDrive() {
        let body = NotifyGatewayClient.tileBody(NotifyTile(title: "Claude Usage")!)
        for key in ["status", "endsIn", "steps", "step", "button"] {
            XCTAssertNil(body[key], "\(key) should not appear at all")
        }
    }

    func testTheTileBodyCarriesItsMetrics() {
        let tile = NotifyTile(
            title: "Claude Usage",
            progress: 42,
            metrics: [NotifyMetric(label: "5h", value: "42", unit: "%", tintHex: "#34C759")!]
        )!
        let body = NotifyGatewayClient.tileBody(tile)
        let metrics = body["metrics"] as? [[String: Any]]

        XCTAssertEqual(metrics?.count, 1)
        XCTAssertEqual(metrics?.first?["label"] as? String, "5h")
        XCTAssertEqual(metrics?.first?["value"] as? String, "42")
        XCTAssertEqual(metrics?.first?["unit"] as? String, "%")
        XCTAssertEqual(metrics?.first?["color"] as? String, "#34C759")
        XCTAssertEqual(body["progress"] as? Double, 42)
    }

    /// The widget is where an unstated field matters most: it lives under its
    /// id until the user removes it, so anything left unsaid survives forever.
    func testTheGaugeBodyStatesANullForEveryFieldExceptTheTitle() {
        let body = NotifyGatewayClient.gaugeBody(NotifyGauge(title: "Claude Usage")!)

        XCTAssertEqual(body["title"] as? String, "Claude Usage")
        for key in ["value", "unit", "detail", "symbol", "tint", "progress"] {
            XCTAssertTrue(body[key] is NSNull, "\(key) should be an explicit null")
        }
    }

    // MARK: - Request building

    /// Built through `URLComponents` rather than interpolation, because the per
    /// device token is an opaque secret that can contain characters a query
    /// string has to escape.
    func testTheTokenIsPercentEncodedIntoTheQuery() throws {
        let url = try NotifyGatewayClient.endpoint(
            host: URL(string: "https://push.getnotifyapp.com")!,
            path: "/live-activity/ABC12345",
            queryItems: [URLQueryItem(name: "token", value: "a b+c/d")]
        )
        XCTAssertEqual(url.path, "/live-activity/ABC12345")
        XCTAssertFalse(url.absoluteString.contains("a b+c/d"))
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "token" }?.value
        XCTAssertEqual(token, "a b+c/d")
    }

    func testAHostWithATrailingSlashDoesNotDoubleTheSeparator() throws {
        let url = try NotifyGatewayClient.endpoint(
            host: URL(string: "https://example.com/")!,
            path: "/widgets/ABC12345",
            queryItems: []
        )
        XCTAssertEqual(url.path, "/widgets/ABC12345")
    }

    /// The gateway accepts 0 to 14400 seconds and rejects anything else, so a
    /// caller's preference is clamped rather than allowed to fail the end call
    /// it is only decorating.
    func testKeepForIsClamped() {
        XCTAssertEqual(NotifyGatewayClient.clampedKeepFor(-10), 0)
        XCTAssertEqual(NotifyGatewayClient.clampedKeepFor(600), 600)
        XCTAssertEqual(
            NotifyGatewayClient.clampedKeepFor(99_999),
            Int(NotifyGatewayClient.maximumKeepFor)
        )
        XCTAssertEqual(NotifyGatewayClient.clampedKeepFor(.nan), 0)
    }

    // MARK: - Refusals that cost no request

    /// A Live Activity aimed at a Mac, a browser or a group fails before a
    /// request exists, with the sentence that names what to paste instead.
    func testALiveActivityAimedAtADeviceThatCannotShowOneFailsLocally() async {
        let client = NotifyGatewayClient(networkClient: NeverCalledClient())
        let link = NotifyDeviceLink(deviceId: "MC12345678901234", token: "s")!
        let tile = NotifyTile(title: "Claude Usage")!

        do {
            _ = try await client.publishTile(tile, link: link, activityId: nil)
            XCTFail("a Mac cannot show a Live Activity")
        } catch let error as NotifyPublishError {
            guard case .liveActivityUnavailable = error else {
                return XCTFail("expected liveActivityUnavailable, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEitherWidgetAimedAtAGroupFailsLocally() async {
        let client = NotifyGatewayClient(networkClient: NeverCalledClient())
        let link = NotifyDeviceLink(deviceId: "GRP12345", token: "s")!

        do {
            _ = try await client.publishGauge(NotifyGauge(title: "Claude Usage")!, link: link, widgetId: nil)
            XCTFail("a group owns no widget list")
        } catch let error as NotifyPublishError {
            guard case .invalidPayload = error else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try await client.publishScreenTile(NotifyTile(title: "Claude Usage")!, link: link, screenWidgetId: nil)
            XCTFail("a group owns no widget list")
        } catch let error as NotifyPublishError {
            guard case .invalidPayload = error else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

/// A transport that fails the test if anything reaches it. Used where the point
/// of the assertion is that no request was ever made.
@MainActor
private struct NeverCalledClient: NotifyHTTPClient {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        XCTFail("no request should have been sent")
        throw URLError(.badURL)
    }
}
