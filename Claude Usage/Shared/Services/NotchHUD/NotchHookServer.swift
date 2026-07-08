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
        connection.start(queue: queue)
        receive(on: connection, parser: HookHTTPParser())
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

            case let .request(_, path, body):
                // Path check is cheap and needs no body parsing; unknown or
                // unauthenticated paths (incl. legacy hooks from the abandoned
                // branch) get an instant 404.
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

    private func respond(_ connection: NWConnection, status: Int) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Payload Too Large"
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
