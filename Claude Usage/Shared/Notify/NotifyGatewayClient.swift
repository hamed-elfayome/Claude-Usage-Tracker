//
//  NotifyGatewayClient.swift
//  Claude Usage
//
//  The only file in the Notify! feature that knows HTTP exists.
//

import Foundation

/// Writes the app's usage state to the Notify! gateway.
///
/// The gateway has no notion of a tile or widget "type": the fields present in the JSON body
/// decide how the thing draws, and an absent field is left alone by the gateway's merge. So this
/// client sends only the fields this app actually drives and never mentions the rest, which is what
/// keeps an update from here stomping something the user configured elsewhere.
///
/// Routes used:
/// - `POST /live-activity/{deviceId|activityId}?token=` for the Lock Screen tile
/// - `POST /widgets/{deviceId|widgetId}?token=` for the gauge widget
/// - `POST /screenwidgets/{deviceId|screenWidgetId}?token=` for the Home Screen widget
/// - `DELETE /live-activity/{activityId}?token=&keepFor=` to end the tile
/// - `GET /link?id=&token=` to check a pasted device link
///
/// There is no bearer token: the per device secret travels in `?token=`, and the gateway answers a
/// missing token, a wrong token, an unknown id and somebody else's id with one identical 403.
struct NotifyGatewayClient: NotifyPublishing {

    /// The gateway host. The initializer takes another only so tests can point
    /// the client at a stub.
    static let defaultHost = URL(string: "https://push.getnotifyapp.com")!

    private static let liveActivityRoute = "/live-activity"
    private static let widgetsRoute = "/widgets"
    private static let screenWidgetsRoute = "/screenwidgets"
    private static let linkRoute = "/link"

    /// The first rung of the gateway's push to start backoff ladder, used when a 429 names no
    /// wait of its own.
    static let defaultBackoff: TimeInterval = 1800

    /// The gateway's own ceiling on how long a finished tile may linger.
    static let maximumKeepFor: TimeInterval = 14400

    private let networkClient: NotifyHTTPClient
    private let host: URL
    private let timeout: TimeInterval

    init(
        networkClient: NotifyHTTPClient = URLSession.shared,
        host: URL = NotifyGatewayClient.defaultHost,
        timeout: TimeInterval = 15
    ) {
        self.networkClient = networkClient
        self.host = host
        self.timeout = timeout
    }

    // MARK: - NotifyPublishing

    /// Starts the tile when `activityId` is nil, otherwise updates that exact tile.
    ///
    /// A start addresses the device id and carries `"new": true`. That flag matters twice over.
    /// It tells the gateway to start a tile of the app's own instead of taking over whichever
    /// tile the user last started from some other script, and it is the documented override for
    /// the sticky dismissal 410, so a tile the user swiped away can be replaced by a fresh one.
    ///
    /// An update addresses the returned `LA…` id and sends content only. No control flag belongs
    /// on an update: `new` there would leave the device with two tiles.
    func publishTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        activityId: String?
    ) async throws -> String {
        // A Mac of either generation and a web push browser are refused by the gateway itself,
        // which answers a start aimed at one with a 400 saying the target device cannot show Live
        // Activities at all, and a group owns no Lock Screen to start one on. So the point of
        // stopping here is not the saved request. It is which sentence the user ends up reading: a
        // 400 coming back from a server reads as the app failing at something it should have
        // managed, while the link's own reason reads as the thing that is actually true about
        // their device, and it names the fix, which is to paste the link from their phone.
        guard link.supportsLiveActivity else {
            throw NotifyPublishError.liveActivityUnavailable(
                link.kind.liveActivityUnsupportedReason
                    ?? "notify.unsupported.live_activity_generic".localized
            )
        }

        var body = Self.tileBody(tile)
        let target: String
        let route: String

        if let activityId {
            target = activityId
            route = "POST \(Self.liveActivityRoute) (update)"
        } else {
            target = link.deviceId
            body["new"] = true
            route = "POST \(Self.liveActivityRoute) (start)"
            LoggingService.shared.logDebug("Notify!: starting a tile on device \(link.deviceId)")
        }

        let url = try Self.endpoint(
            host: host,
            path: "\(Self.liveActivityRoute)/\(target)",
            queryItems: [URLQueryItem(name: "token", value: link.token)]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try Self.encode(body)
        Self.applyWriteHeaders(&request, timeout: timeout)

        let data = try await send(request, route: route, accepting: [200])

        guard let decoded = try? JSONDecoder().decode(LiveActivityWriteResponse.self, from: data) else {
            LoggingService.shared.logError("Notify!: \(route) answered a body the app could not read")
            throw NotifyPublishError.malformedResponse
        }

        // `pushed: false` is a success. The content is stored and delivers the moment the device
        // reports a usable tile token again, so treating it as an error would make the app
        // restart a tile that is already waiting to appear.
        if decoded.pushed == false {
            LoggingService.shared.logDebug("Notify!: tile content stored, no reachable tile token right now")
        }

        guard let identifier = decoded.activityId ?? activityId else {
            throw NotifyPublishError.malformedResponse
        }
        return identifier
    }

    /// Creates the widget when `widgetId` is nil, otherwise updates that exact widget.
    ///
    /// A create carries `"new": true` for the same "never hijack" reason as a tile start: the
    /// device dialect would otherwise write over the one widget already sitting there.
    ///
    /// A create answers 201, but 200 is accepted too and read the same way, because the gateway
    /// answers 200 when the call it received turned out to be an update.
    func publishGauge(
        _ gauge: NotifyGauge,
        link: NotifyDeviceLink,
        widgetId: String?
    ) async throws -> String {
        // Only a group is refused, and only because a group is not a device: it fans a
        // notification out to its members and owns no widget list for one to sit in. Every real
        // device can keep a widget. The gateway is explicit that widgets carry no device type
        // gate and that legacy, `WB` and `MC` ids can all own one, so which of them draws it is
        // Notify!'s business and not a rule for this client to invent.
        //
        // `invalidPayload` rather than `liveActivityUnavailable`, because no Live Activity is
        // involved and that error's remedies, opening the app or waiting out a backoff, would
        // send the user somewhere useless.
        guard link.supportsWidget else {
            throw NotifyPublishError.invalidPayload(
                link.kind.widgetUnsupportedReason
                    ?? "notify.unsupported.widget_generic".localized
            )
        }

        var body = Self.gaugeBody(gauge)
        let target: String
        let route: String
        let accepting: Set<Int>

        if let widgetId {
            target = widgetId
            route = "POST \(Self.widgetsRoute) (update)"
            accepting = [200]
        } else {
            target = link.deviceId
            body["new"] = true
            route = "POST \(Self.widgetsRoute) (create)"
            accepting = [200, 201]
            LoggingService.shared.logDebug("Notify!: creating a widget on device \(link.deviceId)")
        }

        let url = try Self.endpoint(
            host: host,
            path: "\(Self.widgetsRoute)/\(target)",
            queryItems: [URLQueryItem(name: "token", value: link.token)]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try Self.encode(body)
        Self.applyWriteHeaders(&request, timeout: timeout)

        let data = try await send(request, route: route, accepting: accepting)

        guard let decoded = try? JSONDecoder().decode(WidgetWriteResponse.self, from: data),
              let identifier = decoded.widgetId ?? widgetId else {
            LoggingService.shared.logError("Notify!: \(route) answered a body the app could not read")
            throw NotifyPublishError.malformedResponse
        }
        return identifier
    }

    /// Creates the Home Screen widget when `screenWidgetId` is nil, otherwise updates that exact
    /// one.
    ///
    /// The body is the tile's, built by the same `tileBody` the Live Activity uses. That is not a
    /// convenience: the gateway derives this route's content contract from its Live Activity
    /// module, so the two surfaces take the same fields, the same caps and the same merge rules,
    /// and one tile value driving both is the entire point of the feature. A second builder here
    /// could only drift from the first and put two different pictures of one quota on one phone.
    ///
    /// A create carries `"new": true` for the same "never hijack" reason as the other two
    /// surfaces: the device dialect would otherwise write over whichever screen widget is already
    /// there. A create answers 201, and 200 is accepted alongside it exactly as for the gauge,
    /// since the gateway answers 200 when the call it received turned out to be an update.
    func publishScreenTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        screenWidgetId: String?
    ) async throws -> String {
        // Only a group is refused, and for the reason the gauge refuses one: a group is not a
        // device and owns no widget list to write into. Every real device can keep a screen
        // widget, the gateway being explicit that this route carries no device type gate at all
        // and that legacy, `IO`, `WB` and `MC` ids can each own one.
        guard link.supportsScreenWidget else {
            throw NotifyPublishError.invalidPayload(
                link.kind.screenWidgetUnsupportedReason
                    ?? "notify.unsupported.screen_widget_generic".localized
            )
        }

        var body = Self.tileBody(tile)
        let target: String
        let route: String
        let accepting: Set<Int>

        if let screenWidgetId {
            target = screenWidgetId
            route = "POST \(Self.screenWidgetsRoute) (update)"
            accepting = [200]
        } else {
            target = link.deviceId
            body["new"] = true
            route = "POST \(Self.screenWidgetsRoute) (create)"
            accepting = [200, 201]
            LoggingService.shared.logDebug("Notify!: creating a Home Screen widget on device \(link.deviceId)")
        }

        let url = try Self.endpoint(
            host: host,
            path: "\(Self.screenWidgetsRoute)/\(target)",
            queryItems: [URLQueryItem(name: "token", value: link.token)]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try Self.encode(body)
        Self.applyWriteHeaders(&request, timeout: timeout)

        // Two statuses mean something here that they do not mean anywhere else in this client, so
        // they are translated where that difference is known rather than inside the shared
        // `failure` mapping, which every other route would then have to reason about.
        let data: Data
        do {
            data = try await send(request, route: route, accepting: accepting, expected: [503])
        } catch NotifyPublishError.unexpectedStatus(503) {
            // The server side kill switch for Home Screen widgets. While it is off, creates and
            // updates are refused and reads and deletes are deliberately left open so an already
            // placed tile keeps rendering. Nothing is wrong with the app, the credentials or
            // the content, so this must not reach the user reading like a failure, and the remedy
            // is to wait for the day the surface is switched on.
            //
            // The gateway's own sentence does not survive `unexpectedStatus`, which carries a
            // status code and nothing else, and that costs nothing: an empty message picks the
            // error's own "switched off at the moment, the app will try again later" wording,
            // which is the sentence to put in front of a user however the server phrased it.
            throw NotifyPublishError.surfaceSwitchedOff("")
        } catch NotifyPublishError.liveActivityUnavailable(let message) {
            // A 409, which the shared mapping reads as a Live Activity problem because that is
            // what it means on the route it was written for. Here it means the device dialect
            // found several screen widgets and cannot tell which one was meant. This app creates
            // its own with `new` and addresses it by `SW…` id afterwards, so it should never see
            // this, but telling somebody to open the Notify! app about their Live Activities
            // would be a wrong answer to a question about a Home Screen widget.
            throw NotifyPublishError.invalidPayload(message)
        }

        guard let decoded = try? JSONDecoder().decode(ScreenWidgetWriteResponse.self, from: data),
              let identifier = decoded.screenWidgetId ?? screenWidgetId else {
            LoggingService.shared.logError("Notify!: \(route) answered a body the app could not read")
            throw NotifyPublishError.malformedResponse
        }
        return identifier
    }

    /// Ends the tile, leaving it on the Lock Screen for `keepFor` seconds so the final state can
    /// be read.
    ///
    /// A 410 counts as success. It means the tile is already gone, dismissed or ended or reaped,
    /// which is exactly the outcome the caller asked for.
    func endTile(link: NotifyDeviceLink, activityId: String, keepFor: TimeInterval) async throws {
        let url = try Self.endpoint(
            host: host,
            path: "\(Self.liveActivityRoute)/\(activityId)",
            queryItems: [
                URLQueryItem(name: "token", value: link.token),
                URLQueryItem(name: "keepFor", value: String(Self.clampedKeepFor(keepFor))),
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        Self.applyWriteHeaders(&request, timeout: timeout)

        _ = try await send(
            request,
            route: "DELETE \(Self.liveActivityRoute)",
            accepting: [200, 410]
        )
    }

    /// Checks a device id and token pair and describes the device it names.
    ///
    /// The gateway rate limits this route to five calls a minute per IP, so it must only ever run
    /// from an explicit user action such as a "Test connection" button. Nothing on a timer may
    /// call it.
    func deviceInfo(link: NotifyDeviceLink) async throws -> NotifyDeviceInfo {
        let url = try Self.endpoint(
            host: host,
            path: Self.linkRoute,
            queryItems: [
                URLQueryItem(name: "id", value: link.deviceId),
                URLQueryItem(name: "token", value: link.token),
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The only GET in the feature, and its URL carries the device token. URLSession keys its
        // shared cache by the full request URL and backs that cache with a file in ~/Library/Caches,
        // so a cacheable answer would write the secret to disk in plaintext, outside the Keychain
        // this feature is careful to keep it in. Refusing the cache also happens to be the right
        // semantics: "check these credentials right now" must never be answered from a stale copy.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        LoggingService.shared.logDebug("Notify!: checking the link for device \(link.deviceId)")

        let data: Data
        do {
            data = try await send(request, route: "GET \(Self.linkRoute)", accepting: [200])
        } catch NotifyPublishError.unexpectedStatus(404) {
            // This route has an error envelope of its own and answers 404, not 403, for a pair it
            // does not recognise. It gives that same answer for a wrong token and for an id that
            // does not exist, so it cannot be used to enumerate ids. To the person who just pasted
            // their credentials it is the same problem a 403 names, so it gets the same sentence
            // rather than a bare status code.
            throw NotifyPublishError.rejectedCredentials
        }

        guard let decoded = try? JSONDecoder().decode(LinkResponse.self, from: data) else {
            LoggingService.shared.logError("Notify!: GET \(Self.linkRoute) answered a body the app could not read")
            throw NotifyPublishError.malformedResponse
        }

        // The same route describes groups, and a group cannot carry a Live Activity or a widget,
        // so a group link has to be rejected here rather than failing later with a puzzling 400.
        guard decoded.type == "device" else {
            throw NotifyPublishError.invalidPayload(
                "notify.error.link_is_group".localized
            )
        }

        guard let identifier = decoded.id, let name = decoded.name else {
            throw NotifyPublishError.malformedResponse
        }
        return NotifyDeviceInfo(deviceId: identifier, name: name, platform: decoded.platform)
    }

    // MARK: - Transport

    /// Runs one gateway request and returns its body, translating everything that can go wrong
    /// into a `NotifyPublishError` so no caller ever sees a `URLError`.
    ///
    /// `route` is a bare label such as "POST /live-activity (start)". The real URL carries the per
    /// device token and the device id, and neither belongs in a log the user is asked to attach to
    /// a bug report, so only the route and the status code are logged. The device id appears at
    /// debug level only, which never reaches the log file on disk.
    /// `expected` names statuses that are a refusal rather than a fault: they
    /// still throw, but they are logged at info, because writing "error" into
    /// the file a user attaches to a bug report for something the app then
    /// tells them is perfectly normal is how a log stops being trusted. The
    /// Home Screen widget's 503 kill switch is the only one so far.
    private func send(
        _ request: URLRequest,
        route: String,
        accepting: Set<Int>,
        expected: Set<Int> = []
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            // The code and domain, never the description. Every URL in this
            // client carries the device token in its query string, and a
            // transport error's localized description is free to quote the URL
            // it failed on. `LoggingService.logError` is written to a plaintext file users
            // are asked to attach to bug reports, so the description goes to the
            // thrown error, which is shown in the pane and never written down.
            let failure = error as NSError
            LoggingService.shared.logError("Notify!: \(route) could not be reached (\(failure.domain) \(failure.code))")
            throw NotifyPublishError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            LoggingService.shared.logError("Notify!: \(route) answered something that was not an HTTP response")
            throw NotifyPublishError.malformedResponse
        }

        LoggingService.shared.logDebug("Notify!: \(route) answered HTTP \(http.statusCode)")

        guard accepting.contains(http.statusCode) else {
            let mapped = Self.failure(
                status: http.statusCode,
                data: data,
                retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
            )
            if expected.contains(http.statusCode) {
                LoggingService.shared.logInfo("Notify!: \(route) answered HTTP \(http.statusCode), which is expected here")
            } else {
                LoggingService.shared.logError("Notify!: \(route) failed with HTTP \(http.statusCode)")
            }
            throw mapped
        }

        return data
    }

    // MARK: - Request Building

    /// Builds a gateway URL through `URLComponents` rather than string interpolation, because the
    /// per device token is an opaque secret that can contain characters a query string has to
    /// escape.
    static func endpoint(host: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw NotifyPublishError.invalidPayload("notify.error.bad_host".localized)
        }

        // A host given with a trailing slash would otherwise produce a doubled separator.
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw NotifyPublishError.invalidPayload("notify.error.bad_host".localized)
        }
        return url
    }

    private static func applyWriteHeaders(_ request: inout URLRequest, timeout: TimeInterval) {
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// `JSONSerialization` rather than `JSONEncoder`, matching every other HTTP body in the app.
    /// The bodies are sparse dictionaries whose keys depend on which Domain fields are populated,
    /// which a `Codable` type would express as a wall of optionals and custom encoding.
    static func encode(_ body: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw NotifyPublishError.invalidPayload("notify.error.encode_failed".localized)
        }
    }

    /// The tile's content fields, stating a null for anything the Domain type left nil.
    ///
    /// Both the Live Activity and the Home Screen widget are written with this, because the
    /// gateway builds both routes' content contracts from one module and accepts either body on
    /// either route unchanged.
    ///
    /// `status`, `endsIn`, `steps`, `step` and `button` are deliberately never mentioned. Those
    /// are the fields the "leave it alone" rule is actually for: an absent field is left alone by
    /// the gateway's merge, so staying silent about them is what lets an update from here share a
    /// tile with whatever else the user set up.
    ///
    /// `metrics` has no query spelling at all: the gateway reads it from the JSON body only.
    static func tileBody(_ tile: NotifyTile) -> [String: Any] {
        var body: [String: Any] = ["title": tile.title]

        // Every field the app drives is stated on every write, as an explicit
        // null when it has no value. The gateway merges rather than replaces, so
        // omitting a field it already holds freezes the old value instead of
        // clearing it: a reset countdown would keep ticking beside a quota that
        // no longer reports one, and a bar would keep the last percentage after
        // the headline became a credit balance with no percentage at all.
        body["body"] = tile.body ?? NSNull()
        body["symbol"] = tile.symbolName ?? NSNull()
        body["tint"] = tile.tintHex ?? NSNull()
        body["progress"] = tile.progress ?? NSNull()
        body["trailing"] = tile.trailing ?? NSNull()

        if tile.metrics.isEmpty {
            body["metrics"] = NSNull()
        } else {
            body["metrics"] = tile.metrics.map { metric -> [String: Any] in
                var item: [String: Any] = ["label": metric.label, "value": metric.value]
                if let unit = metric.unit { item["unit"] = unit }
                if let color = metric.tintHex { item["color"] = color }
                return item
            }
        }
        return body
    }

    /// The widget's content fields, stating a null for anything the Domain type left nil.
    ///
    /// The widget is the surface where this matters most. A tile is short lived and gets restarted,
    /// but the widget the app creates lives under its `WG…` id until the user removes it, so any
    /// field left unstated survives forever. A gauge showing a credit balance has no percentage and
    /// no percent sign, and saying so is the only way to take the previous ring off the screen.
    ///
    /// `title` is the exception: the gateway treats it as the widget's identity and refuses to
    /// clear it, so it is always a value and never a null.
    static func gaugeBody(_ gauge: NotifyGauge) -> [String: Any] {
        var body: [String: Any] = ["title": gauge.title]
        body["value"] = gauge.value ?? NSNull()
        body["unit"] = gauge.unit ?? NSNull()
        body["detail"] = gauge.detail ?? NSNull()
        body["symbol"] = gauge.symbolName ?? NSNull()
        body["tint"] = gauge.tintHex ?? NSNull()
        body["progress"] = gauge.progress ?? NSNull()
        return body
    }

    /// The gateway accepts 0 to 14400 seconds and rejects anything else, so a caller's preference
    /// is clamped rather than allowed to fail the end call it is only decorating.
    static func clampedKeepFor(_ keepFor: TimeInterval) -> Int {
        guard keepFor.isFinite else { return 0 }
        return Int(min(maximumKeepFor, max(0, keepFor)))
    }

    // MARK: - Error Mapping

    /// Turns any answer the caller did not accept into the matching Domain error.
    ///
    /// Static, and taking the raw body, so tests can drive every status code and every shape of
    /// error body through it without standing up a network stub.
    static func failure(status: Int, data: Data, retryAfterHeader: String?) -> NotifyPublishError {
        let body = try? JSONDecoder().decode(GatewayFailure.self, from: data)
        let message = body?.message ?? body?.error ?? ""

        switch status {
        case 400:
            return .invalidPayload(message)
        case 403:
            // Missing, wrong, unknown and somebody else's are one indistinguishable answer here.
            return .rejectedCredentials
        case 409:
            return .liveActivityUnavailable(message)
        case 410:
            return .tileGone
        case 429:
            return .backoff(
                retryAfter: retryAfter(bodySeconds: body?.retryAfterSeconds, header: retryAfterHeader),
                openingTheAppMayHelp: body?.openingTheAppMayHelp ?? false
            )
        case 502:
            // "unknown" means Apple never answered, so a tile may well exist. Retrying a start
            // would risk a second tile, which is why this keeps the id for a later poll instead.
            if body?.deliveryState == "unknown" {
                return .deliveryUnconfirmed(activityId: body?.activityId)
            }
            // "not-delivered" means no tile exists and starting again is safe, but not
            // necessarily useful. The gateway counts every unanswered start toward a push to
            // start ladder that reaches six hours, so a start that is refused is treated as a
            // wait rather than as something to try again on the next tick. Its own
            // retryAfterSeconds is the wait when it names one, and when it does not, the
            // contract's own reading is that retrying unchanged is pointless, so the ladder's
            // first rung is used rather than no wait at all.
            if body?.deliveryState == "not-delivered" {
                return .backoff(
                    retryAfter: retryAfter(bodySeconds: body?.retryAfterSeconds, header: retryAfterHeader),
                    openingTheAppMayHelp: body?.openingTheAppMayHelp ?? false
                )
            }
            return .unexpectedStatus(502)
        default:
            return .unexpectedStatus(status)
        }
    }

    /// How long to wait after a 429.
    ///
    /// The body's own number wins because the gateway computes it from the backoff ladder it is
    /// actually enforcing. The `Retry-After` header is the HTTP fallback, and only its numeric
    /// form is read: the HTTP date form would need a clock this app cannot trust to agree with
    /// the server's. With neither present, 30 minutes is the ladder's first rung and so the safest
    /// guess available.
    static func retryAfter(bodySeconds: Double?, header: String?) -> TimeInterval {
        if let bodySeconds, bodySeconds.isFinite, bodySeconds > 0 {
            return bodySeconds
        }
        if let header,
           let seconds = Double(header.trimmingCharacters(in: .whitespacesAndNewlines)),
           seconds.isFinite, seconds > 0 {
            return seconds
        }
        return defaultBackoff
    }
}

// MARK: - Response Models

/// The shared error envelope, `{"error": ..., "message": ...}`, plus the extra fields the 429 and
/// 502 answers add on top of it.
private struct GatewayFailure: Decodable {
    let error: String?
    let message: String?
    let retryAfterSeconds: Double?
    let openingTheAppMayHelp: Bool?
    let deliveryState: String?
    let activityId: String?
}

/// A start or an update of the Live Activity. A start always names the new `LA…` id; an update
/// echoes it and adds `pushed`.
private struct LiveActivityWriteResponse: Decodable {
    let activityId: String?
    let pushed: Bool?
}

/// The `Widget` object a create (201) and an update (200) both answer with. Only the id is read:
/// the echoed content is what the app just sent.
private struct WidgetWriteResponse: Decodable {
    let widgetId: String?
}

/// The `ScreenWidget` object, answered by a create (201) and an update (200) alike. Only the id is
/// read, for the reason the widget's is: the rest of the object is the content the app just sent
/// back again, plus a `staleAt` the phone owns and the app has no decision to make about.
private struct ScreenWidgetWriteResponse: Decodable {
    let screenWidgetId: String?
}

/// `GET /link`, which answers flat snake_case. Only the four fields the app needs are read, and
/// none of those four has an underscore in it, so no key mapping is required.
private struct LinkResponse: Decodable {
    let type: String?
    let id: String?
    let name: String?
    let platform: String?
}
