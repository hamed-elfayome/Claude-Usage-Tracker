//
//  LocalServerService.swift
//  Claude Usage
//
//  An opt-in, read-only HTTP server that exposes the current Claude usage
//  snapshot to trusted devices on the local network (e.g. a companion mobile
//  app). See `Claude Usage/Views/Settings/App/MobileAppView.swift` for the
//  pairing UI.
//
//  Security model
//  ──────────────
//  • Disabled by default; must be explicitly enabled by the user in Settings.
//  • Every request must present a matching `Authorization: Bearer <token>`
//    (or `?token=` query param). The token is generated locally and only
//    leaves the machine via the QR pairing code the user chooses to show.
//  • Read-only: the only data endpoint returns the already-computed
//    `ClaudeUsage` value that the menu bar already displays.
//  • The Claude session key NEVER leaves this machine — the phone only ever
//    sees the derived usage numbers.
//

import Foundation
import Network

final class LocalServerService {
    static let shared = LocalServerService()

    /// Version of the wire contract consumed by client apps. Bump when the
    /// JSON shape changes in a backwards-incompatible way.
    static let apiVersion = "v1"

    /// Default TCP port. Chosen to avoid common dev ports; user-overridable.
    static let defaultPort: UInt16 = 47600

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeusagetracker.localserver", qos: .utility)

    private(set) var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    /// Starts the server only if the user has enabled it in Settings.
    func startIfEnabled() {
        guard SharedDataStore.shared.loadLocalServerEnabled() else {
            LoggingService.shared.log("LocalServer: disabled, not starting")
            return
        }
        start()
    }

    func start() {
        stop()

        let rawPort = UInt16(SharedDataStore.shared.loadLocalServerPort())
        let port = NWEndpoint.Port(rawValue: rawPort == 0 ? Self.defaultPort : rawPort)
            ?? NWEndpoint.Port(rawValue: Self.defaultPort)!

        // Ensure a token exists before we begin accepting connections.
        _ = SharedDataStore.shared.loadOrCreateLocalServerToken()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Bind on all interfaces so devices on the LAN can reach us.
            let listener = try NWListener(using: params, on: port)

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    LoggingService.shared.log("LocalServer: listening on port \(port.rawValue)")
                case .failed(let error):
                    self?.isRunning = false
                    LoggingService.shared.logError("LocalServer: listener failed: \(error.localizedDescription)")
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            LoggingService.shared.logError("LocalServer: failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// Restart to pick up a changed port or token.
    func restart() {
        start()
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Accumulate bytes until the end of the HTTP request headers (`\r\n\r\n`).
    /// We only support GET, so the body (if any) is irrelevant.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
                self.respond(toHeaders: headerData, on: connection)
            } else if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    // MARK: - Routing

    private func respond(toHeaders headerData: Data, on connection: NWConnection) {
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            send(status: "400 Bad Request", json: ["error": "invalid_request"], on: connection)
            return
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            send(status: "400 Bad Request", json: ["error": "invalid_request"], on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", json: ["error": "invalid_request"], on: connection)
            return
        }

        let method = String(parts[0])
        let rawTarget = String(parts[1])
        let (path, query) = Self.splitTarget(rawTarget)

        guard method == "GET" else {
            send(status: "405 Method Not Allowed", json: ["error": "method_not_allowed"], on: connection)
            return
        }

        // Authenticate every request.
        guard isAuthorized(headerLines: lines, query: query) else {
            send(status: "401 Unauthorized", json: ["error": "unauthorized"], on: connection)
            return
        }

        switch path {
        case "/\(Self.apiVersion)/ping":
            send(status: "200 OK", json: [
                "ok": true,
                "app": "claude-usage-tracker",
                "apiVersion": Self.apiVersion
            ], on: connection)

        case "/\(Self.apiVersion)/usage":
            sendUsage(on: connection)

        default:
            send(status: "404 Not Found", json: ["error": "not_found"], on: connection)
        }
    }

    // MARK: - Auth

    private func isAuthorized(headerLines: [String], query: [String: String]) -> Bool {
        let expected = SharedDataStore.shared.loadOrCreateLocalServerToken()
        guard !expected.isEmpty else { return false }

        var presented: String?
        for line in headerLines {
            let lower = line.lowercased()
            if lower.hasPrefix("authorization:") {
                let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
                if value.lowercased().hasPrefix("bearer ") {
                    presented = String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if presented == nil { presented = query["token"] }

        guard let token = presented else { return false }
        return Self.constantTimeEquals(token, expected)
    }

    // MARK: - Usage payload

    private func sendUsage(on connection: NWConnection) {
        let usage = DataStore.shared.loadUsage()
        let profileName = ProfileManager.shared.activeProfile?.name

        let response = UsageResponse(
            apiVersion: Self.apiVersion,
            serverTime: Date(),
            profileName: profileName,
            hasData: usage != nil,
            usage: usage
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]

        do {
            let body = try encoder.encode(response)
            send(status: "200 OK", body: body, contentType: "application/json", on: connection)
        } catch {
            send(status: "500 Internal Server Error", json: ["error": "encode_failed"], on: connection)
        }
    }

    /// Wire envelope around `ClaudeUsage`. Dates are ISO-8601; `userTimezone`
    /// encodes as its identifier string (e.g. "America/New_York").
    private struct UsageResponse: Encodable {
        let apiVersion: String
        let serverTime: Date
        let profileName: String?
        let hasData: Bool
        let usage: ClaudeUsage?
    }

    // MARK: - Response writing

    private func send(status: String, json: [String: Any], on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        send(status: status, body: body, contentType: "application/json", on: connection)
    }

    private func send(status: String, body: Data, contentType: String, on connection: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "\r\n"

        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let qIndex = target.firstIndex(of: "?") else { return (target, [:]) }
        let path = String(target[target.startIndex..<qIndex])
        let queryString = String(target[target.index(after: qIndex)...])
        var query: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                query[key] = value
            }
        }
        return (path, query)
    }

    /// Length-independent comparison to avoid leaking the token via timing.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }

    // MARK: - Network info (for the pairing UI)

    /// Best-guess primary LAN IPv4 address (e.g. "192.168.1.42"), or nil.
    static func primaryLANAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [String: String] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = pointer {
            defer { pointer = ptr.pointee.ifa_next }
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            // Skip loopback and virtual interfaces.
            guard name != "lo0", !name.hasPrefix("utun"), !name.hasPrefix("bridge") else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostBuffer, socklen_t(hostBuffer.count),
                nil, 0, NI_NUMERICHOST
            )
            if result == 0 {
                candidates[name] = String(cString: hostBuffer)
            }
        }

        // Prefer Wi-Fi/Ethernet (en0/en1) when present.
        for preferred in ["en0", "en1"] {
            if let addr = candidates[preferred] { address = addr; break }
        }
        if address == nil { address = candidates.values.first }
        return address
    }
}
