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
        guard let value, !(value is String) else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Extracts the billing result from newline-delimited JSON-RPC stdout.
/// Notifications are ignored. This does not launch the CLI.
enum GrokCLIProtocol {
    enum Failure: Equatable {
        case authenticationRequired
        case methodUnsupported
        case invalidResponse
    }

    static func billingPayload(from lines: [String]) -> Data? {
        guard case .payload(let data) = classify(lines) else { return nil }
        return data
    }

    static func failure(from lines: [String]) -> Failure? {
        guard case .failure(let failure) = classify(lines) else { return nil }
        return failure
    }

    private static func classify(_ lines: [String]) -> Classification {
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["id"] as? Int == 2 else { continue }
            if let error = object["error"] as? [String: Any] {
                let code = (error["code"] as? NSNumber)?.intValue
                let message = (error["message"] as? String)?.lowercased() ?? ""
                if code == -32601 { return .failure(.methodUnsupported) }
                if message.contains("authentication required") || message.contains("grok login") {
                    return .failure(.authenticationRequired)
                }
                return .failure(.invalidResponse)
            }
            if object["result"] != nil, let data = line.data(using: .utf8) {
                return .payload(data)
            }
            return .failure(.invalidResponse)
        }
        return .failure(.invalidResponse)
    }

    private enum Classification {
        case payload(Data)
        case failure(Failure)
    }
}
