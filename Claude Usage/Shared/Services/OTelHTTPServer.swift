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

            // Debug: write to file since os_log isn't visible
            let debugMsg = "[\(Date())] Received \(content?.count ?? 0) bytes, total \(accumulated.count), isComplete=\(isComplete)\n"
            let debugPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-usage-tracker/otel_debug.log")
            if let fh = try? FileHandle(forWritingTo: debugPath) {
                fh.seekToEndOfFile()
                fh.write(Data(debugMsg.utf8))
                fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: debugPath.path, contents: Data(debugMsg.utf8))
            }
            LoggingService.shared.log("OTelHTTPServer: Received \(content?.count ?? 0) bytes, total \(accumulated.count), isComplete=\(isComplete)")

            // Check for body size limit
            if accumulated.count > Constants.OTel.maxRequestBodySize {
                self.sendResponse(connection: connection, status: "413 Payload Too Large", body: "{\"error\":\"Request too large\"}")
                return
            }

            // Try to parse the HTTP request
            if let parsed = self.parseHTTPRequest(data: accumulated) {
                let parseMsg = "[\(Date())] PARSED: \(parsed.method) \(parsed.path) body=\(parsed.body.count) bytes\n"
                if let fh = try? FileHandle(forWritingTo: debugPath) { fh.seekToEndOfFile(); fh.write(Data(parseMsg.utf8)); fh.closeFile() }
                LoggingService.shared.log("OTelHTTPServer: Parsed request: \(parsed.method) \(parsed.path) body=\(parsed.body.count) bytes")
                self.routeRequest(connection: connection, method: parsed.method, path: parsed.path, body: parsed.body)
            } else if isComplete {
                LoggingService.shared.log("OTelHTTPServer: Connection complete, trying fallback parser on \(accumulated.count) bytes")
                // Connection closed — try parsing as chunked with all data received
                if let parsed = self.parseHTTPRequestFinal(data: accumulated) {
                    LoggingService.shared.log("OTelHTTPServer: Fallback parsed: \(parsed.method) \(parsed.path) body=\(parsed.body.count) bytes")
                    self.routeRequest(connection: connection, method: parsed.method, path: parsed.path, body: parsed.body)
                } else {
                    LoggingService.shared.log("OTelHTTPServer: Fallback parse failed, dumping first 200 bytes: \(String(data: accumulated.prefix(200), encoding: .utf8) ?? "non-utf8")")
                    connection.cancel()
                }
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

        // Detect transfer encoding and content length
        var contentLength: Int?
        var isChunked = false
        let headerLines = headerStr.split(separator: "\r\n")
        for line in headerLines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valueStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(valueStr)
            } else if lower.hasPrefix("transfer-encoding:") {
                let valueStr = line.dropFirst("transfer-encoding:".count).trimmingCharacters(in: .whitespaces).lowercased()
                isChunked = valueStr.contains("chunked")
            }
        }

        let bodyStart = separatorRange.upperBound
        let remainingData = data[bodyStart...]

        if isChunked {
            // Check if we've received the terminal chunk (0\r\n\r\n)
            let terminator = Data("0\r\n\r\n".utf8)
            guard remainingData.range(of: terminator) != nil else {
                return nil // Need more data — terminal chunk not yet received
            }

            // Extract JSON body from between chunked framing
            let bodyData = Data(remainingData)
            guard let bodyStr = String(data: bodyData, encoding: .utf8),
                  let jsonStart = bodyStr.firstIndex(of: "{"),
                  let jsonData = extractJSON(from: bodyStr[jsonStart...]) else {
                return nil
            }
            return HTTPRequest(method: method, path: path, body: jsonData)
        } else {
            let expectedLength = contentLength ?? 0
            let availableBody = data.count - (bodyStart - data.startIndex)

            // If we haven't received the full body yet, return nil to request more data
            if availableBody < expectedLength {
                return nil
            }

            let body = data[bodyStart..<(bodyStart + expectedLength)]
            return HTTPRequest(method: method, path: path, body: Data(body))
        }
    }

    /// Decodes HTTP chunked transfer encoding.
    /// Each chunk: hex-size\r\n<data>\r\n, terminated by 0\r\n\r\n
    private func decodeChunkedBody(_ data: Data) -> Data? {
        var result = Data()
        var position = data.startIndex
        let crlf = Data("\r\n".utf8)

        while position < data.endIndex {
            // Find the end of the chunk size line
            guard let crlfRange = data[position...].range(of: crlf) else {
                return nil // Need more data
            }

            guard let sizeStr = String(data: data[position..<crlfRange.lowerBound], encoding: .utf8),
                  let chunkSize = UInt(sizeStr.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }

            // 0-length chunk = end of body
            if chunkSize == 0 {
                return result
            }

            let chunkStart = crlfRange.upperBound
            let chunkEnd = chunkStart + Int(chunkSize)

            // Need more data if chunk isn't fully received (chunk + trailing \r\n)
            if chunkEnd + crlf.count > data.endIndex {
                return nil
            }

            result.append(data[chunkStart..<chunkEnd])
            position = chunkEnd + crlf.count
        }

        return nil // Need more data
    }

    /// Fallback parser for when connection is complete — extracts JSON body
    /// regardless of transfer encoding by finding the JSON object in the raw data.
    private func parseHTTPRequestFinal(data: Data) -> HTTPRequest? {
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

        // Extract everything after headers and find JSON object
        let bodyRegion = Data(data[separatorRange.upperBound...])
        guard let bodyStr = String(data: bodyRegion, encoding: .utf8) else { return nil }

        // Find the JSON object boundaries (handles chunked framing around it)
        guard let jsonStart = bodyStr.firstIndex(of: "{"),
              let jsonData = extractJSON(from: bodyStr[jsonStart...]) else {
            return nil
        }

        return HTTPRequest(method: method, path: path, body: jsonData)
    }

    /// Extract a complete JSON object from a string, handling nested braces
    private func extractJSON(from str: Substring) -> Data? {
        var depth = 0
        var endIndex = str.startIndex
        for (i, char) in zip(str.indices, str) {
            if char == "{" { depth += 1 }
            else if char == "}" { depth -= 1 }
            if depth == 0 {
                endIndex = str.index(after: i)
                return String(str[str.startIndex..<endIndex]).data(using: .utf8)
            }
        }
        return nil
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
        // Debug: dump body to file
        // Write full body to separate file for analysis
        let bodyPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-usage-tracker/otel_last_body.json")
        try? body.write(to: bodyPath)
        let bodyDump = "[\(Date())] BODY (\(body.count) bytes) written to otel_last_body.json\n"
        let debugPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-usage-tracker/otel_debug.log")
        if let fh = try? FileHandle(forWritingTo: debugPath) { fh.seekToEndOfFile(); fh.write(Data(bodyDump.utf8)); fh.closeFile() }

        guard let batch = OTelEventParser.parse(data: body) else {
            let failMsg = "[\(Date())] PARSE FAILED\n"
            if let fh = try? FileHandle(forWritingTo: debugPath) { fh.seekToEndOfFile(); fh.write(Data(failMsg.utf8)); fh.closeFile() }
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
