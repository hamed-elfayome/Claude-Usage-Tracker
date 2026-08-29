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
        /// Body exceeds the cap on an otherwise well-formed request. The
        /// caller owns the response: for an authorized path that is a drained
        /// 200-and-drop, never an error status — the cap is our limitation,
        /// not the sender's mistake. `remainingBytes` is how much body is
        /// still on the wire.
        case oversizeRequest(path: String, remainingBytes: Int)
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
    private let pathAuthorizer: ((String) -> Bool)?

    /// `pathAuthorizer` is consulted at header-framing time, BEFORE any body
    /// byte is buffered — an unauthorized peer must not be able to make us
    /// accumulate its payload. `nil` skips the early check (pure-parser tests).
    init(maxHeaderBytes: Int = Constants.NotchHUD.maxHeaderBytes,
         maxBodyBytes: Int = Constants.NotchHUD.maxBodyBytes,
         pathAuthorizer: ((String) -> Bool)? = nil) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
        self.pathAuthorizer = pathAuthorizer
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
                switch parseHeader(upTo: range.lowerBound) {
                case let .error(status):
                    finished = true
                    return .error(status: status)
                case .oversizeRequest:
                    // Re-derive with the body bytes that rode in alongside
                    // the header already subtracted.
                    finished = true
                    let received = buffer.count - range.upperBound
                    return .oversizeRequest(path: path ?? "",
                                            remainingBytes: max(0, (contentLength ?? 0) - received))
                default:
                    break
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

        // Authorize the path BEFORE looking at Content-Length so an
        // unauthorized peer can neither park a body in our buffer nor learn
        // the size cap (404 for them, always).
        if let authorize = pathAuthorizer, !authorize(parsedPath) {
            return .error(status: 404)
        }

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

        self.method = parsedMethod
        self.path = parsedPath
        self.contentLength = contentLength

        guard contentLength <= maxBodyBytes else {
            // Placeholder — feed() rebuilds this with the true remaining count.
            return .oversizeRequest(path: parsedPath, remainingBytes: contentLength)
        }
        return .needMoreData
    }
}
