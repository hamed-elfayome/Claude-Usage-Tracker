import Foundation
import CoreFoundation

extension AutoStartSessionService {
    private struct SessionWindow {
        let percentage: Double
        let resetTime: Date
        let hasOpenWindow: Bool
    }

    func parseUsageResponse(_ data: Data) throws -> (usage: ClaudeUsage, hasOpenWindow: Bool) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError(code: .apiParsingFailed, message: "Failed to parse usage data", isRecoverable: false)
        }
        let window = parseSessionWindow(json["five_hour"] as? [String: Any])
        let sevenDay = json["seven_day"] as? [String: Any]
        var usage = ClaudeUsage.empty
        usage.sessionPercentage = window.percentage
        usage.sessionResetTime = window.resetTime
        usage.weeklyLimit = Constants.weeklyLimit
        usage.weeklyPercentage = try parseWeeklyUtilization(sevenDay?["utilization"])
        usage.weeklyResetTime = parseResetTime(sevenDay?["resets_at"]) ?? usage.weeklyResetTime
        let tokens = (Double(usage.weeklyLimit) * (usage.weeklyPercentage / 100.0)).rounded(.towardZero)
        guard let weeklyTokens = Int(exactly: tokens) else {
            throw AppError(
                code: .apiParsingFailed,
                message: "Weekly utilization is out of range; auto-start skipped",
                isRecoverable: true
            )
        }
        usage.weeklyTokensUsed = weeklyTokens
        let opus = parseModelWeeklyUsage(json["seven_day_opus"] as? [String: Any])
        usage.opusWeeklyPercentage = opus.percentage
        usage.opusWeeklyTokensUsed = Int(Double(usage.weeklyLimit) * (opus.percentage / 100.0))
        let sonnet = parseModelWeeklyUsage(json["seven_day_sonnet"] as? [String: Any])
        usage.sonnetWeeklyPercentage = sonnet.percentage
        usage.sonnetWeeklyTokensUsed = Int(Double(usage.weeklyLimit) * (sonnet.percentage / 100.0))
        usage.sonnetWeeklyResetTime = sonnet.resetTime
        return (usage, window.hasOpenWindow)
    }

    private func parseSessionWindow(
        _ json: [String: Any]?
    ) -> SessionWindow {
        let percentage = json?["utilization"].map(parseUtilization) ?? 0
        var resetTime = Date().addingTimeInterval(Constants.sessionWindow)
        var hasOpenWindow = false
        // A window may still round to 0%. Its live reset time distinguishes it
        // from a closed window; the synthesized fallback alone cannot do that.
        if let resetsAt = json?["resets_at"] as? String {
            resetTime = parseResetTime(resetsAt) ?? resetTime
            hasOpenWindow = resetTime > Date()
        }
        return SessionWindow(percentage: percentage, resetTime: resetTime, hasOpenWindow: hasOpenWindow)
    }

    private func parseModelWeeklyUsage(_ json: [String: Any]?) -> (percentage: Double, resetTime: Date?) {
        let percentage = json?["utilization"].map(parseUtilization) ?? 0
        return (percentage, parseResetTime(json?["resets_at"]))
    }

    private func parseResetTime(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value)
        if date == nil {
            LoggingService.shared.logWarning(
                "Invalid auto-start reset timestamp; retaining the existing reset fallback"
            )
        }
        return date
    }

    private func parseWeeklyUtilization(_ value: Any?) throws -> Double {
        let percentage: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            percentage = number.doubleValue
        } else if let string = value as? String {
            percentage = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: ""))
        } else {
            percentage = nil
        }
        guard let percentage = percentage, percentage.isFinite, percentage >= 0 else {
            throw AppError(
                code: .apiParsingFailed,
                message: "Weekly utilization is missing or invalid; auto-start skipped",
                isRecoverable: true
            )
        }
        return percentage
    }

    private func parseUtilization(_ value: Any) -> Double {
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let stringValue = value as? String {
            let cleaned = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let parsed = Double(cleaned) {
                return parsed
            }
        }
        return 0.0
    }

    /// Parse the completion response (SSE format) to extract session reset time from messageLimit.windows.5h

    func parseCompletionResponseForResetTime(_ data: Data) -> Date? {
        guard let responseString = String(data: data, encoding: .utf8) else { return nil }

        // The response is SSE format - find the last completion event with messageLimit data
        let lines = responseString.components(separatedBy: "\n")
        for line in lines.reversed() {
            if line.hasPrefix("data: "),
               let jsonStart = line.index(line.startIndex, offsetBy: 6, limitedBy: line.endIndex),
               let jsonData = String(line[jsonStart...]).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let messageLimit = json["messageLimit"] as? [String: Any],
               let windows = messageLimit["windows"] as? [String: Any],
               let fiveH = windows["5h"] as? [String: Any],
               let resetsAt = fiveH["resets_at"] as? Double {
                return Date(timeIntervalSince1970: resetsAt)
            }
        }
        return nil
    }
}
