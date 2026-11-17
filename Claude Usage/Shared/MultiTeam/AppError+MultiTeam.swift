import Foundation

extension AppError {
    /// Seconds from the `Retry-After: N` line in technicalDetails, if present and >= 0.
    var retryAfterSeconds: TimeInterval? {
        guard let details = technicalDetails else { return nil }
        for line in details.split(separator: "\n") where line.hasPrefix("Retry-After:") {
            let value = line.dropFirst("Retry-After:".count).trimmingCharacters(in: .whitespaces)
            if let secs = Int(value), secs >= 0 { return TimeInterval(secs) }
        }
        return nil
    }

    var isCloudflareChallenge: Bool { code == .apiServiceUnavailable }
    var isMembershipFailure: Bool { code == .apiUnauthorized || code == .apiNotFound }
    var isRateLimited: Bool { code == .apiRateLimited }
}
