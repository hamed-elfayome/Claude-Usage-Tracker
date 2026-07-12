//
//  HookHTTPParser.swift
//  Claude Usage
//
//  Minimal incremental HTTP/1.1 request parser for the notch hook listener.
//  Deliberately tiny: POST-only, Content-Length framing, hard size caps.
//  Pure value type with no I/O so it is fully unit-testable.
//

import Foundation

struct HookHTTPParser {
    enum ParseResult: Equatable {
        /// Keep feeding bytes.
        case needMoreData
        /// A complete request was framed.
        case request(method: String, path: String, body: Data)
        /// Protocol violation — respond with this HTTP status and close.
        case error(status: Int)
    }

    private var buffer = Data()
    private var headerEndIndex: Int?
    private var method: String?
    private var path: String?
    private var contentLength: Int?
    private var finished = false

    private let maxHeaderBytes: Int
    private let maxBodyBytes: Int

    init(maxHeaderBytes: Int = Constants.NotchHUD.maxHeaderBytes,
         maxBodyBytes: Int = Constants.NotchHUD.maxBodyBytes) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
    }

    /// Feed the next chunk of bytes from the connection.
    mutating func feed(_ data: Data) -> ParseResult {
        guard !finished else { return .error(status: 400) }
        buffer.append(data)

        // Phase 1: frame the header block.
        if headerEndIndex == nil {
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                headerEndIndex = range.upperBound
                if range.upperBound > maxHeaderBytes {
                    finished = true
                    return .error(status: 431)
                }
                if case let .error(status) = parseHeader(upTo: range.lowerBound) {
                    finished = true
                    return .error(status: status)
                }
            } else if buffer.count > maxHeaderBytes {
                finished = true
                return .error(status: 431)
            } else {
                return .needMoreData
            }
        }

        // Phase 2: accumulate the body until Content-Length is satisfied.
        guard let headerEnd = headerEndIndex,
              let method = method, let path = path, let contentLength = contentLength else {
            finished = true
            return .error(status: 400)
        }

        let bodyBytesReceived = buffer.count - headerEnd
        if bodyBytesReceived < contentLength {
            return .needMoreData
        }

        finished = true
        let body = buffer.subdata(in: headerEnd..<(headerEnd + contentLength))
        return .request(method: method, path: path, body: body)
    }

    private mutating func parseHeader(upTo end: Int) -> ParseResult {
        guard let headerText = String(data: buffer.subdata(in: 0..<end), encoding: .utf8) else {
            return .error(status: 400)
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .error(status: 400) }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return .error(status: 400) }
        let parsedMethod = String(parts[0])
        let parsedPath = String(parts[1])

        guard parsedMethod == "POST" else { return .error(status: 405) }

        var length: Int?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            if pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(pair[1].trimmingCharacters(in: .whitespaces))
            }
        }
        // Hooks always send Content-Length; anything else is malformed for us.
        guard let contentLength = length, contentLength >= 0 else { return .error(status: 400) }
        guard contentLength <= maxBodyBytes else { return .error(status: 413) }

        self.method = parsedMethod
        self.path = parsedPath
        self.contentLength = contentLength
        return .needMoreData
    }
}
