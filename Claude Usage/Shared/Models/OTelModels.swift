//
//  OTelModels.swift
//  Claude Usage - OpenTelemetry Data Models
//
//  OTLP wire format structs for decoding incoming telemetry,
//  plus app-domain structs for storage and display.
//

import Foundation

// MARK: - OTLP Wire Format (JSON decoding)

/// Top-level OTLP logs export request
struct OTLPLogsExportRequest: Codable {
    let resourceLogs: [OTLPResourceLogs]?
}

struct OTLPResourceLogs: Codable {
    let resource: OTLPResource?
    let scopeLogs: [OTLPScopeLogs]?
}

struct OTLPResource: Codable {
    let attributes: [OTLPKeyValue]?
}

struct OTLPScopeLogs: Codable {
    let scope: OTLPScope?
    let logRecords: [OTLPLogRecord]?
}

struct OTLPScope: Codable {
    let name: String?
    let version: String?
}

struct OTLPLogRecord: Codable {
    let timeUnixNano: String?
    let severityNumber: Int?
    let severityText: String?
    let body: OTLPAnyValue?
    let attributes: [OTLPKeyValue]?
}

struct OTLPKeyValue: Codable {
    let key: String
    let value: OTLPAnyValue?
}

/// OTLP AnyValue union type — handles stringValue, intValue (as String), doubleValue, boolValue
struct OTLPAnyValue: Codable {
    let stringValue: String?
    let intValue: String?      // OTLP encodes int64 as string
    let doubleValue: Double?
    let boolValue: Bool?

    /// Extract as String
    var asString: String? {
        if let s = stringValue { return s }
        if let i = intValue { return i }
        if let d = doubleValue { return String(d) }
        if let b = boolValue { return String(b) }
        return nil
    }

    /// Extract as Double
    var asDouble: Double? {
        if let d = doubleValue { return d }
        if let i = intValue { return Double(i) }
        if let s = stringValue { return Double(s) }
        return nil
    }

    /// Extract as Int
    var asInt: Int? {
        if let i = intValue { return Int(i) }
        if let d = doubleValue { return Int(d) }
        if let s = stringValue { return Int(s) }
        return nil
    }

    /// Extract as Bool
    var asBool: Bool? {
        if let b = boolValue { return b }
        if let s = stringValue { return s == "true" }
        return nil
    }
}

// MARK: - App Domain Models

/// A single API request event from Claude Code telemetry
struct OTelAPIRequest: Identifiable {
    let id: Int64
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

/// A tool result event from Claude Code telemetry
struct OTelToolResult: Identifiable {
    let id: Int64
    let timestamp: Date
    let sessionId: String?
    let toolName: String
    let success: Bool
    let durationMs: Int
}

/// Summary of API usage for a single day
struct OTelDaySummary: Identifiable {
    let id: String  // date string "YYYY-MM-DD"
    let date: Date
    let totalCostUSD: Double
    let totalRequests: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheReadTokens: Int
    let totalCacheCreationTokens: Int
    let modelBreakdown: [ModelSummary]

    struct ModelSummary: Identifiable {
        let id: String  // model name
        let model: String
        let requests: Int
        let costUSD: Double
        let inputTokens: Int
        let outputTokens: Int
    }
}
