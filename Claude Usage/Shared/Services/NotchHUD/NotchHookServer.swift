//
//  NotchHookServer.swift
//  Claude Usage
//
//  Loopback-only HTTP listener receiving Claude Code hook events for the
//  notch HUD. STRICTLY READ-ONLY by construction: every accepted request is
//  answered with an immediate `200 {}` BEFORE its JSON is even parsed, no
//  connection is ever held open, and no code path exists that could emit a
//  hook decision payload. Compare with the abandoned feature/dynamic-island
//  branch, whose server answered permission requests — the security hole this
//  rewrite deliberately makes impossible.
//
//  All networking runs on a dedicated serial queue; the only main-actor hop
//  is delivering parsed events to NotchSessionStore.
//

import Foundation
import Network

final class NotchHookServer {
    static let shared = NotchHookServer()

    private let queue = DispatchQueue(label: "com.claudeusagetracker.notchhud.server")
    private var listener: NWListener?
    private var retryCount = 0
    private var desiredRunning = false
    /// Connections currently being serviced; bounds concurrent peers.
    private var activeConnections = 0

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self = self, self.listener == nil else { return }
            self.desiredRunning = true
            self.retryCount = 0
            self.startListenerLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.desiredRunning = false
            self.listener?.cancel()
            self.listener = nil
            Task { @MainActor in NotchSessionStore.shared.serverStatus = .stopped }
        }
    }

    /// Settings "Retry" button after a port-busy failure.
    func retry() {
        queue.async { [weak self] in
            guard let self = self, self.desiredRunning, self.listener == nil else { return }
            self.retryCount = 0
            self.startListenerLocked()
        }
    }

    /// Must be called on `queue`.
    private func startListenerLocked() {
        guard desiredRunning else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            // Loopback only — never expose the listener on the network.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(Constants.NotchHUD.host),
                port: NWEndpoint.Port(rawValue: Constants.NotchHUD.port)!
            )
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            LoggingService.shared.logError("NotchHookServer: failed to create listener", error: error)
            scheduleRetryOrFail()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            retryCount = 0
            LoggingService.shared.log("NotchHookServer: listening on \(Constants.NotchHUD.baseURL)")
            Task { @MainActor in NotchSessionStore.shared.serverStatus = .running }
        case .failed(let error):
            LoggingService.shared.logError("NotchHookServer: listener failed", error: error)
            listener?.cancel()
            listener = nil
            scheduleRetryOrFail()
        default:
            break
        }
    }

    /// Bounded backoff (1s/2s/4s), then surface port-busy in settings.
    /// Must be called on `queue`.
    private func scheduleRetryOrFail() {
        guard desiredRunning else { return }
        guard retryCount < 3 else {
            Task { @MainActor in NotchSessionStore.shared.serverStatus = .portBusy }
            return
        }
        let delay = pow(2.0, Double(retryCount))
        retryCount += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.desiredRunning, self.listener == nil else { return }
            self.startListenerLocked()
        }
    }

    // MARK: - Connections

    private func handleNewConnection(_ connection: NWConnection) {
        // Hard cap on concurrent peers — a client holding sockets open must
        // not exhaust us. Real hook connections live for milliseconds.
        guard activeConnections < Constants.NotchHUD.maxConcurrentConnections else {
            connection.cancel()
            return
        }
        activeConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.activeConnections -= 1
                connection.stateUpdateHandler = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        // Deadline: whatever happens, the connection dies after this long.
        // cancel() on an already-cancelled connection is a safe no-op.
        queue.asyncAfter(deadline: .now() + Constants.NotchHUD.connectionDeadline) {
            connection.cancel()
        }
        // The parser authorizes the path at header-framing time, so a peer
        // without the token can never occupy body-buffer memory.
        let parser = HookHTTPParser(pathAuthorizer: { [weak self] path in
            self?.validatedEventSuffix(for: path) != nil
        })
        receive(on: connection, parser: parser)
    }

    private func receive(on connection: NWConnection, parser: HookHTTPParser) {
        var parser = parser
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }

            guard let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            switch parser.feed(data) {
            case .needMoreData:
                if isComplete { connection.cancel(); return }
                self.receive(on: connection, parser: parser)

            case let .error(status):
                self.respond(connection, status: status)

            case let .oversizeRequest(path, remainingBytes):
                // Authorized sender, body over our cap. That is OUR
                // limitation — drain the wire, answer 200, drop the event.
                // An error status here would surface as a red hook error in
                // the sender's Claude Code session (the pre-cap behavior:
                // HTTP 413 on every large file Read).
                LoggingService.shared.log(
                    "NotchHookServer: dropping oversize \(path) payload (\(remainingBytes) bytes unread)")
                self.drainThenAcknowledge(connection, remainingBytes: remainingBytes)

            case let .request(_, path, body):
                // Belt-and-braces re-check; the parser already 404s
                // unauthorized paths (incl. legacy hooks from the abandoned
                // branch) before buffering any body.
                guard let suffix = self.validatedEventSuffix(for: path) else {
                    self.respond(connection, status: 404)
                    return
                }
                // Respond FIRST — the hook must never wait on our processing,
                // and a malformed body must never punish Claude Code.
                self.respond(connection, status: 200)
                self.dispatchEvent(suffix: suffix, body: body)
            }
        }
    }

    /// Read and discard the remaining body so the client's send completes,
    /// then acknowledge with 200. Closing without draining would reset the
    /// client mid-send and punish it with a socket error instead. Draining is
    /// bounded by `maxDrainBytes` and the connection deadline.
    private func drainThenAcknowledge(_ connection: NWConnection, remainingBytes: Int) {
        guard remainingBytes > 0 else {
            respond(connection, status: 200)
            return
        }
        guard remainingBytes <= Constants.NotchHUD.maxDrainBytes else {
            // Absurd Content-Length — never produced by real hooks. Answer
            // and close; not worth reading megabytes for.
            respond(connection, status: 200)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }
            let received = data?.count ?? 0
            if received >= remainingBytes || isComplete {
                self.respond(connection, status: 200)
            } else {
                self.drainThenAcknowledge(connection, remainingBytes: remainingBytes - received)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 431: reason = "Request Header Fields Too Large"
        default: reason = "Bad Request"
        }
        let body = status == 200 ? "{}" : ""
        let response = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
            + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Event dispatch

    /// Expected path shape: /hook/<token>/<event-suffix>. Returns the event
    /// suffix when the path is well-formed, token-authenticated, and allowed.
    private func validatedEventSuffix(for path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count == 3,
              components[0] == "hook",
              components[1] == SharedDataStore.shared.notchHUDPathToken(),
              NotchHookEvent.pathSuffixes.contains(components[2]) else {
            return nil
        }
        return components[2]
    }

    private func dispatchEvent(suffix: String, body: Data) {
        guard let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let event = NotchHookEvent.from(pathSuffix: suffix, payload: payload) else {
            LoggingService.shared.log("NotchHookServer: dropping malformed \(suffix) payload")
            return
        }

        Task { @MainActor in
            NotchSessionStore.shared.apply(event)
        }
    }
}
