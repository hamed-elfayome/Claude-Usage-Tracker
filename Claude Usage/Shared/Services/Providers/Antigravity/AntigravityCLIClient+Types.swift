//
//  AntigravityCLIClient+Types.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  DTOs for `agy --print /usage --output-format json`. The format is not
//  documented by Google, so every field decodes on its own (per-field try?):
//  a new or malformed field must never fail the whole response.
//
//  Observed shape (agy, 2026-11):
//  { "status": "SUCCESS", "error": "...",
//    "command": { "name": "usage", "data": { "groups": [
//      { "name": "Claude and GPT models", "buckets": [
//        { "id": "3p-5h", "name": "Five Hour Limit Remaining", "window": "5h",
//          "remaining_fraction": 0.97, "reset_time": "2026-11-27T11:11:45Z" } ] } ] } } }
//

import Foundation

struct AntigravityUsageResponse: Decodable, Equatable {
    /// "SUCCESS" or "ERROR"; kept raw so unknown values pass through.
    let status: String?
    let error: String?
    let groups: [AntigravityQuotaGroup]

    private enum CodingKeys: String, CodingKey { case status, error, command }
    private enum CommandKeys: String, CodingKey { case name, data }
    private enum DataKeys: String, CodingKey { case groups }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = AntigravityDecoding.field(String.self, c, .status, "AntigravityUsageResponse")
        error = AntigravityDecoding.field(String.self, c, .error, "AntigravityUsageResponse")
        let command = try? c.nestedContainer(keyedBy: CommandKeys.self, forKey: .command)
        let data = try? command?.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        groups = data.flatMap { AntigravityDecoding.lossyArray(AntigravityQuotaGroup.self, $0, .groups) } ?? []
    }

    init(status: String?, error: String? = nil, groups: [AntigravityQuotaGroup]) {
        self.status = status
        self.error = error
        self.groups = groups
    }

    var isSuccess: Bool { status?.uppercased() == "SUCCESS" }
}

struct AntigravityQuotaGroup: Decodable, Equatable {
    let name: String?
    let buckets: [AntigravityQuotaBucket]

    private enum CodingKeys: String, CodingKey { case name, buckets }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = AntigravityDecoding.field(String.self, c, .name, "AntigravityQuotaGroup")
        buckets = AntigravityDecoding.lossyArray(AntigravityQuotaBucket.self, c, .buckets) ?? []
    }

    init(name: String?, buckets: [AntigravityQuotaBucket]) {
        self.name = name
        self.buckets = buckets
    }
}

struct AntigravityQuotaBucket: Decodable, Equatable {
    /// Stable bucket id, e.g. `3p-5h`, `3p-weekly`, `gemini-weekly`.
    let id: String?
    /// "5h" or "weekly"; raw so unknown windows pass through.
    let window: String?
    /// 1 = untouched, 0 = used up.
    let remainingFraction: Double?
    /// ISO 8601. `1970-01-01T00:00:00Z` means the window has not started.
    let resetTime: Date?

    private enum CodingKeys: String, CodingKey {
        case id, window
        case remainingFraction = "remaining_fraction"
        case resetTime = "reset_time"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = AntigravityDecoding.field(String.self, c, .id, "AntigravityQuotaBucket")
        window = AntigravityDecoding.field(String.self, c, .window, "AntigravityQuotaBucket")
        remainingFraction = AntigravityDecoding.field(Double.self, c, .remainingFraction, "AntigravityQuotaBucket")
        resetTime = AntigravityDecoding.field(String.self, c, .resetTime, "AntigravityQuotaBucket")
            .flatMap { AntigravityDecoding.parseDate($0) }
    }

    init(id: String?, window: String?, remainingFraction: Double?, resetTime: Date?) {
        self.id = id
        self.window = window
        self.remainingFraction = remainingFraction
        self.resetTime = resetTime
    }
}

enum AntigravityDecoding {
    /// Decodes one optional field; a present-but-malformed value becomes nil
    /// and is logged (key name only, never the value) so schema drift is noticed.
    static func field<T: Decodable, K: CodingKey>(
        _ type: T.Type, _ c: KeyedDecodingContainer<K>, _ key: K, _ dto: String
    ) -> T? {
        guard c.contains(key) else { return nil }
        if (try? c.decodeNil(forKey: key)) == true { return nil }
        do {
            return try c.decode(T.self, forKey: key)
        } catch {
            LoggingService.shared.logWarning("\(dto): field '\(key.stringValue)' failed to decode")
            return nil
        }
    }

    /// Decodes an array, skipping elements that fail instead of failing the array.
    static func lossyArray<T: Decodable, K: CodingKey>(
        _ type: T.Type, _ c: KeyedDecodingContainer<K>, _ key: K
    ) -> [T]? {
        guard var array = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
        var result: [T] = []
        while !array.isAtEnd {
            if let element = try? array.decode(T.self) {
                result.append(element)
            } else {
                _ = try? array.decode(AnyDecodable.self)  // skip the bad element
            }
        }
        return result
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private struct AnyDecodable: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
