//
//  AntigravityUsageMapper.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation

enum AntigravityUsageMapper {

    static let sessionWindow: TimeInterval = 5 * 60 * 60
    static let weeklyWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Bucket ids per pool: (session / 5-hour, weekly). Matched exactly first;
    /// other buckets in the group (e.g. `gemini-argon-wtu-weekly`) are ignored.
    static func bucketIds(for pool: AntigravityPool) -> (session: String, weekly: String) {
        switch pool {
        case .thirdParty: return ("3p-5h", "3p-weekly")
        case .gemini: return ("gemini-5h", "gemini-weekly")
        }
    }

    static func idPrefix(for pool: AntigravityPool) -> String {
        switch pool {
        case .thirdParty: return "3p-"
        case .gemini: return "gemini-"
        }
    }

    /// The buckets for `pool`, by exact id first, then by `window` inside the
    /// pool's group (found by id prefix). `nil` when the pool is absent.
    static func buckets(for pool: AntigravityPool, in response: AntigravityUsageResponse)
        -> (session: AntigravityQuotaBucket?, weekly: AntigravityQuotaBucket?)? {
        let all = response.groups.flatMap(\.buckets)
        let ids = bucketIds(for: pool)
        var session = all.first { $0.id == ids.session }
        var weekly = all.first { $0.id == ids.weekly }

        if session == nil || weekly == nil {
            let prefix = idPrefix(for: pool)
            let group = response.groups.first { $0.buckets.contains { $0.id?.hasPrefix(prefix) == true } }
            let known = Set([ids.session, ids.weekly])
            let others = (group?.buckets ?? []).filter { !known.contains($0.id ?? "") && $0.id?.hasPrefix(prefix) != false }
            if session == nil { session = others.first { $0.window == "5h" } }
            // Only fall back for weekly when the pool has no exact weekly bucket
            // AND exactly one other weekly bucket, so a model-specific weekly
            // limit is never mistaken for the pool's.
            if weekly == nil {
                let weeklies = others.filter { $0.window == "weekly" }
                if weeklies.count == 1 { weekly = weeklies.first }
            }
        }

        if session == nil && weekly == nil { return nil }
        return (session, weekly)
    }

    /// Maps `pool` to `ClaudeUsage`. `nil` when the response has no bucket for it.
    ///
    /// `previous` anchors reset times of windows that have not started: agy
    /// reports those either as the epoch or as a rolling "now + window" that
    /// moves on every call, and MenuBarManager treats a reset-time jump of more
    /// than a few minutes as a reset. Reusing the previous (still future)
    /// value keeps it stable, as the Codex mapping does.
    static func mapToUsage(
        _ response: AntigravityUsageResponse,
        pool: AntigravityPool,
        previous: ClaudeUsage? = nil,
        now: Date = Date()
    ) -> ClaudeUsage? {
        guard let (session, weekly) = buckets(for: pool, in: response) else { return nil }

        var usage = ClaudeUsage.empty
        usage.weeklyLimit = 0  // .empty uses a placeholder token limit; agy reports none
        usage.sessionLimit = 0

        usage.hasSessionLimit = session != nil
        usage.sessionPercentage = usedPercent(session)
        usage.sessionResetTime = resetTime(session, previous: previous?.sessionResetTime, window: sessionWindow, now: now)

        usage.hasWeeklyLimit = weekly != nil
        usage.weeklyPercentage = usedPercent(weekly)
        usage.weeklyResetTime = resetTime(weekly, previous: previous?.weeklyResetTime, window: weeklyWindow, now: now)

        usage.quotas = allQuotas(response, menuBarPool: pool, now: now)
        usage.planType = nil
        usage.lastUpdated = now
        usage.userTimezone = .current
        return usage
    }

    /// Every pool's buckets, the menu bar's pool first, then the others in
    /// declaration order; session before weekly within a pool. Windows that
    /// have not started get no reset time.
    static func allQuotas(_ response: AntigravityUsageResponse, menuBarPool: AntigravityPool, now: Date) -> [UsageQuota] {
        let pools = [menuBarPool] + AntigravityPool.allCases.filter { $0 != menuBarPool }
        return pools.flatMap { pool -> [UsageQuota] in
            guard let (session, weekly) = buckets(for: pool, in: response) else { return [] }
            return [(session, UsageQuota.Window.session), (weekly, .weekly)].compactMap { bucket, window in
                guard let bucket else { return nil }
                return UsageQuota(
                    id: bucket.id ?? "\(idPrefix(for: pool))\(window.rawValue)",
                    titleKey: quotaTitleKey(for: pool),
                    window: window,
                    usedPercentage: usedPercent(bucket),
                    resetTime: isStarted(bucket, now: now) ? bucket.resetTime : nil
                )
            }
        }
    }

    static func quotaTitleKey(for pool: AntigravityPool) -> String {
        switch pool {
        case .thirdParty: return "antigravity.quota.third_party"
        case .gemini: return "antigravity.quota.gemini"
        }
    }

    static func usedPercent(_ bucket: AntigravityQuotaBucket?) -> Double {
        guard let fraction = bucket?.remainingFraction, fraction.isFinite else { return 0 }
        return min(max((1 - fraction) * 100, 0), 100)
    }

    /// A window "has started" when it has been used and reports a real,
    /// future reset time. Otherwise the previous future reset is kept, or a
    /// now-relative placeholder is used.
    static func resetTime(_ bucket: AntigravityQuotaBucket?, previous: Date?, window: TimeInterval, now: Date) -> Date {
        if let bucket, isStarted(bucket, now: now), let reset = bucket.resetTime {
            return reset
        }
        if let previous, previous > now { return previous }
        return now.addingTimeInterval(window)
    }

    static func isStarted(_ bucket: AntigravityQuotaBucket, now: Date) -> Bool {
        guard let fraction = bucket.remainingFraction, fraction < 1 else { return false }
        guard let reset = bucket.resetTime, reset.timeIntervalSince1970 > 0, reset > now else { return false }
        return true
    }
}
