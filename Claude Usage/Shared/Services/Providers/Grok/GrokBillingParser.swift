import CoreFoundation
import Foundation

/// A weekly SuperGrok quota reading. `usedPercent` is the share already
/// consumed; the UI derives the remainder. A missing reset is not invented.
struct GrokWeeklyQuota: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    let plan: String?
}

/// Turns a Grok CLI billing payload into a weekly quota, or nil when the
/// payload does not actually report one. A prepaid balance alone is not a quota.
enum GrokBillingParser {
    static func quota(from data: Data) -> GrokWeeklyQuota? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["error"] != nil, object["result"] == nil {
            return nil
        }
        let payload = object["result"] as? [String: Any] ?? object
        guard let config = payload["config"] as? [String: Any],
              let percent = number(config["creditUsagePercent"]),
              (0...100).contains(percent),
              let period = config["currentPeriod"] as? [String: Any],
              period["type"] as? String == "USAGE_PERIOD_TYPE_WEEKLY" else {
            return nil
        }
        return GrokWeeklyQuota(
            usedPercent: percent,
            resetsAt: date(period["end"] as? String),
            plan: payload["subscription_tier"] as? String
        )
    }

    static func usage(from quota: GrokWeeklyQuota, now: Date = Date()) -> ClaudeUsage {
        var usage = ClaudeUsage.empty
        usage.weeklyLimit = 0
        usage.sessionPercentage = 0
        usage.sessionTokensUsed = 0
        usage.sessionLimit = 0
        usage.hasSessionLimit = false
        usage.hasWeeklyLimit = true
        usage.weeklyPercentage = quota.usedPercent
        usage.weeklyTokensUsed = 0
        usage.planType = quota.plan
        usage.lastUpdated = now
        if let reset = quota.resetsAt {
            usage.weeklyResetTime = reset
            usage.weeklyResetKnown = true
        } else {
            usage.weeklyResetKnown = false
        }
        return usage
    }

    private static func number(_ value: Any?) -> Double? {
        // JSONSerialization bridges both numbers and booleans to NSNumber.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// `nil` means this line is not a reply to our outstanding request.
nonisolated enum GrokCLIProtocol {
    static func reply(to id: Int, in line: Data) -> Result<Data, GrokCLIError>? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["method"] == nil,
              let replyID = object["id"] as? NSNumber, CFGetTypeID(replyID) != CFBooleanGetTypeID(),
              replyID == NSNumber(value: id) else { return nil }

        guard object["jsonrpc"] as? String == "2.0" else { return .failure(.unavailable) }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.lowercased() ?? ""
            if message.contains("authentication required") || message.contains("grok login") {
                return .failure(.authenticationRequired)
            }
            return .failure(.unavailable)
        }
        guard object["error"] == nil, object["result"] is [String: Any] else { return .failure(.unavailable) }
        return .success(line)
    }
}
