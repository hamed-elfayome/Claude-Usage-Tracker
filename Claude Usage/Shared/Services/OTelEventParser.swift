//
//  OTelEventParser.swift
//  Claude Usage - OpenTelemetry Event Parser
//
//  Decodes OTLP JSON body, extracts resource attributes,
//  routes log records by event.name to produce typed parsed events.
//

import Foundation

// MARK: - Parsed Output Types

struct ParsedAPIRequest {
    let timestamp: Date
    let sessionId: String?
    let model: String
    let costUSD: Double
    let durationMs: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let speed: String?
    let userEmail: String?
    let organizationId: String?
}

struct ParsedToolResult {
    let timestamp: Date
    let sessionId: String?
    let toolName: String
    let success: Bool
    let durationMs: Int
}

struct ParsedOTelBatch {
    let apiRequests: [ParsedAPIRequest]
    let toolResults: [ParsedToolResult]
}

// MARK: - Parser

enum OTelEventParser {

    /// Parse an OTLP JSON body into typed events
    static func parse(data: Data) -> ParsedOTelBatch? {
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(OTLPLogsExportRequest.self, from: data) else {
            return nil
        }

        var apiRequests: [ParsedAPIRequest] = []
        var toolResults: [ParsedToolResult] = []

        guard let resourceLogs = request.resourceLogs else {
            return ParsedOTelBatch(apiRequests: [], toolResults: [])
        }

        for resourceLog in resourceLogs {
            // Extract resource-level attributes (session.id, user.email, org.id)
            let resourceAttrs = attributeMap(from: resourceLog.resource?.attributes)

            let sessionId = resourceAttrs["session.id"]?.asString
            let userEmail = resourceAttrs["user.email"]?.asString
            let organizationId = resourceAttrs["org.id"]?.asString

            guard let scopeLogs = resourceLog.scopeLogs else { continue }
            for scopeLog in scopeLogs {
                guard let logRecords = scopeLog.logRecords else { continue }
                for record in logRecords {
                    let eventName = record.body?.asString ?? ""
                    let timestamp = parseTimestamp(record.timeUnixNano)
                    let attrs = attributeMap(from: record.attributes)

                    switch eventName {
                    case "claude_code.api_request":
                        let parsed = ParsedAPIRequest(
                            timestamp: timestamp,
                            sessionId: sessionId,
                            model: attrs["model"]?.asString ?? "unknown",
                            costUSD: attrs["cost_usd"]?.asDouble ?? 0,
                            durationMs: attrs["duration_ms"]?.asInt ?? 0,
                            inputTokens: attrs["input_tokens"]?.asInt ?? 0,
                            outputTokens: attrs["output_tokens"]?.asInt ?? 0,
                            cacheReadTokens: attrs["cache_read_tokens"]?.asInt ?? 0,
                            cacheCreationTokens: attrs["cache_creation_tokens"]?.asInt ?? 0,
                            speed: attrs["speed"]?.asString,
                            userEmail: userEmail ?? attrs["user.email"]?.asString,
                            organizationId: organizationId ?? attrs["org.id"]?.asString
                        )
                        apiRequests.append(parsed)

                    case "claude_code.tool_result":
                        let parsed = ParsedToolResult(
                            timestamp: timestamp,
                            sessionId: sessionId,
                            toolName: attrs["tool_name"]?.asString ?? "unknown",
                            success: attrs["success"]?.asBool ?? true,
                            durationMs: attrs["duration_ms"]?.asInt ?? 0
                        )
                        toolResults.append(parsed)

                    default:
                        // Unknown event types silently skipped (forward-compatible)
                        break
                    }
                }
            }
        }

        return ParsedOTelBatch(apiRequests: apiRequests, toolResults: toolResults)
    }

    // MARK: - Helpers

    /// Convert attribute array to dictionary for fast lookup
    private static func attributeMap(from attributes: [OTLPKeyValue]?) -> [String: OTLPAnyValue] {
        guard let attrs = attributes else { return [:] }
        var map: [String: OTLPAnyValue] = [:]
        for kv in attrs {
            if let value = kv.value {
                map[kv.key] = value
            }
        }
        return map
    }

    /// Parse OTLP nanosecond timestamp string to Date
    private static func parseTimestamp(_ nanoString: String?) -> Date {
        guard let nanoStr = nanoString, let nanos = UInt64(nanoStr) else {
            return Date()
        }
        let seconds = TimeInterval(nanos) / 1_000_000_000.0
        return Date(timeIntervalSince1970: seconds)
    }
}
