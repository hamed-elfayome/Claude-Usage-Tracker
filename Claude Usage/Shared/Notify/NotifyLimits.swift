//
//  NotifyLimits.swift
//  Claude Usage
//
//  The Notify! gateway's field limits, kept in one place.
//

import Foundation

/// The Notify! gateway's field limits, kept in one place so every value type
/// enforces the same rules at construction instead of hoping the caller did.
///
/// The gateway rejects an oversized string with a 400 naming the field, and
/// clamps an out of range number rather than rejecting it. We do both here: a
/// quota label that happens to be long should shorten, never fail to reach the
/// phone.
enum NotifyLimits {
    // Live Activity tile
    static let titleLength = 120
    static let bodyLength = 300
    static let symbolLength = 64
    static let trailingLength = 40
    static let metricCount = 6
    static let metricLabelLength = 24
    static let metricValueLength = 16
    static let metricUnitLength = 8

    // Lock Screen widget
    static let widgetTitleLength = 120
    static let widgetValueLength = 40
    static let widgetUnitLength = 12
    static let widgetDetailLength = 120

    /// Trims whitespace, drops NUL (the gateway rejects it outright), shortens
    /// to `maximum` characters, and reports an empty result as `nil` so an
    /// absent field is never sent as `""`.
    static func text(_ value: String?, maximum: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > maximum else { return cleaned }
        return String(cleaned.prefix(maximum))
    }

    /// Clamps a percentage into the 0 to 100 the gateway accepts. A quota can
    /// legitimately report a negative remainder when the user is over the
    /// limit, and that reads as an empty bar rather than an error.
    static func progress(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(100, max(0, value))
    }

    /// Normalizes an accent color to the `#RRGGBB` (or `#AARRGGBB`) the gateway
    /// accepts, returning nil for anything else so a bad color is dropped
    /// rather than failing the whole publish.
    static func tint(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6 || digits.count == 8 else { return nil }
        guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + digits.uppercased()
    }
}
