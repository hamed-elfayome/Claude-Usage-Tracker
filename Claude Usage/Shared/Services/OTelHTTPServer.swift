//
//  OTelHTTPServer.swift
//  Claude Usage - Lightweight OTLP HTTP Receiver
//
//  Network.framework NWListener bound to 127.0.0.1:4318 (localhost only).
//  Minimal HTTP/1.1 parser. Routes POST /v1/logs to OTelEventParser + OTelDatabase.
//

import Foundation
import Network

final class OTelHTTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeusage.otelserver", qos: .utility)
    private let database: OTelDatabase
    private let port: UInt16
    private var onEventReceived: (() -> Void)?

    private(set) var isRunning = false

    init(database: OTelDatabase, port: UInt16 = Constants.OTel.defaultPort, onEventReceived: (() -> Void)? = nil) {
        self.database = database
        self.port = port
        self.onEventReceived = onEventReceived
    }

    // MARK: - Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        // Bind to localhost only — never network-reachable
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: params)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                LoggingService.shared.log("OTelHTTPServer: Listening on 127.0.0.1:\(self?.port ?? 0)")
                self?.isRunning = true
            case .failed(let error):
                LoggingService.shared.logError("OTelHTTPServer: Listener failed: \(error)")
                self?.isRunning = false
            case .cancelled:
                LoggingService.shared.log("OTelHTTPServer: Listener cancelled")
                self?.isRunning = false
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        LoggingService.shared.log("OTelHTTPServer: Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        // Read the full HTTP request
        receiveHTTPRequest(connection: connection, buffer: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                LoggingService.shared.log("OTelHTTPServer: Receive error: \(error)")
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let content {
                accumulated.append(content)
            }

            // Check for body size limit
            if accumulated.count > Constants.OTel.maxRequestBodySize {
                self.sendResponse(connection: connection, status: "413 Payload Too Large", body: "{\"error\":\"Request too large\"}")
                return
            }

            // Try to parse the HTTP request
            if let parsed = self.parseHTTPRequest(data: accumulated) {
                self.routeRequest(connection: connection, method: parsed.method, path: parsed.path, body: parsed.body)
            } else if isComplete {
                // Connection closed before we got a full request
                connection.cancel()
            } else {
                // Need more data
                self.receiveHTTPRequest(connection: connection, buffer: accumulated)
            }
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private func parseHTTPRequest(data: Data) -> HTTPRequest? {
        // Find header/body separator \r\n\r\n
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerStr.split(separator: "\r\n", maxSplits: 1)
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Find Content-Length
        var contentLength = 0
        let headerLines = headerStr.split(separator: "\r\n")
        for line in headerLines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valueStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(valueStr) ?? 0
                break
            }
        }

        let bodyStart = separatorRange.upperBound
        let availableBody = data.count - (bodyStart - data.startIndex)

        // If we haven't received the full body yet, return nil to request more data
        if availableBody < contentLength {
            return nil
        }

        let body = data[bodyStart..<(bodyStart + contentLength)]
        return HTTPRequest(method: method, path: path, body: Data(body))
    }

    // MARK: - Routing

    private func routeRequest(connection: NWConnection, method: String, path: String, body: Data) {
        if method == "POST" && path == "/v1/logs" {
            handleLogsEndpoint(connection: connection, body: body)
        } else {
            sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Not found\"}")
        }
    }

    private func handleLogsEndpoint(connection: NWConnection, body: Data) {
        guard let batch = OTelEventParser.parse(data: body) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid OTLP JSON\"}")
            return
        }

        if !batch.apiRequests.isEmpty {
            database.insertAPIRequests(batch.apiRequests)
        }
        if !batch.toolResults.isEmpty {
            database.insertToolResults(batch.toolResults)
        }

        let totalEvents = batch.apiRequests.count + batch.toolResults.count
        if totalEvents > 0 {
            onEventReceived?()
        }

        let responseBody = "{\"partialSuccess\":{\"rejectedLogRecords\":0}}"
        sendResponse(connection: connection, status: "200 OK", body: responseBody)
    }

    // MARK: - Response

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let response = """
            HTTP/1.1 \(status)\r
            Content-Type: application/json\r
            Content-Length: \(bodyData.count)\r
            Connection: close\r
            \r\n
            """

        var responseData = Data(response.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
