import Foundation

struct CodexUsage: Codable, Equatable {
    let requestLimit: Int
    let requestsRemaining: Int
    let tokenLimit: Int
    let tokensRemaining: Int
    let requestResetTime: Date
    let tokenResetTime: Date
    let lastUpdated: Date

    var requestPercentageUsed: Double {
        guard requestLimit > 0 else { return 0 }
        return Double(requestLimit - requestsRemaining) / Double(requestLimit) * 100.0
    }

    var tokenPercentageUsed: Double {
        guard tokenLimit > 0 else { return 0 }
        return Double(tokenLimit - tokensRemaining) / Double(tokenLimit) * 100.0
    }

    var requestsUsed: Int {
        requestLimit - requestsRemaining
    }

    var tokensUsed: Int {
        tokenLimit - tokensRemaining
    }

    static func parseResetDuration(_ value: String) -> TimeInterval? {
        var total: TimeInterval = 0
        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            guard let number = scanner.scanDouble() else { return nil }
            if scanner.scanString("h") != nil {
                total += number * 3600
            } else if scanner.scanString("ms") != nil {
                total += number / 1000
            } else if scanner.scanString("m") != nil {
                total += number * 60
            } else if scanner.scanString("s") != nil {
                total += number
            } else {
                return nil
            }
        }
        return total
    }

    static func fromHeaders(_ headers: [String: String], at date: Date = Date()) -> CodexUsage? {
        guard let limitReq = headers["x-ratelimit-limit-requests"].flatMap(Int.init),
              let remainReq = headers["x-ratelimit-remaining-requests"].flatMap(Int.init),
              let limitTok = headers["x-ratelimit-limit-tokens"].flatMap(Int.init),
              let remainTok = headers["x-ratelimit-remaining-tokens"].flatMap(Int.init),
              let resetReqStr = headers["x-ratelimit-reset-requests"],
              let resetTokStr = headers["x-ratelimit-reset-tokens"],
              let resetReqDuration = parseResetDuration(resetReqStr),
              let resetTokDuration = parseResetDuration(resetTokStr)
        else { return nil }

        return CodexUsage(
            requestLimit: limitReq,
            requestsRemaining: remainReq,
            tokenLimit: limitTok,
            tokensRemaining: remainTok,
            requestResetTime: date.addingTimeInterval(resetReqDuration),
            tokenResetTime: date.addingTimeInterval(resetTokDuration),
            lastUpdated: date
        )
    }
}
