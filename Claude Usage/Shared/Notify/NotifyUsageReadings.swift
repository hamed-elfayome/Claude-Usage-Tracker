//
//  NotifyUsageReadings.swift
//  Claude Usage
//
//  Flattens a profile's usage into the readings the payload builder takes.
//

import Foundation

/// Turns the active profile's `ClaudeUsage` into the flat readings the payload
/// builder works on.
///
/// This is the seam between the app's model and the Notify! feature. `ClaudeUsage`
/// is a wide struct of named windows, some of which a given provider never
/// fills in; `NotifyQuotaReading` is a flat list of windows that are actually
/// reporting something. Keeping the translation in one pure function means the
/// builder never has to know which provider it is looking at, and the whole
/// mapping is testable without a network or a profile.
///
/// Only windows the provider genuinely reports are included. A per-model
/// weekly window that a provider never fills in would otherwise sort as a
/// healthy 100% and take one of the tile's six slots away from a number that
/// matters.
enum NotifyUsageReadings {

    /// Every quota window worth publishing for one profile's usage.
    ///
    /// - Parameters:
    ///   - usage: the profile's most recent usage.
    ///   - provider: which provider produced it, for the label and capabilities.
    ///   - now: the moment to measure expiry against, injected for tests.
    static func readings(
        from usage: ClaudeUsage,
        provider: Provider,
        now: Date = Date()
    ) -> [NotifyQuotaReading] {
        let descriptor = provider.descriptor
        let providerId = provider.rawValue
        let providerName = descriptor.displayName
        var quotas: [NotifyQuota] = []

        // The rolling session window. `effectiveSessionPercentage` already
        // reports an expired window as 0% used, which is the right answer: a
        // window that rolled over while the Mac was asleep is full again, and
        // publishing the stale percentage would put a red ring on a phone for a
        // limit that no longer applies.
        let sessionUsed = usage.sessionResetTime < now ? 0 : usage.sessionPercentage
        quotas.append(
            NotifyQuota(
                key: QuotaKey.session,
                label: "notify.window.session".localized,
                percentRemaining: remaining(from: sessionUsed),
                resetsAt: usage.sessionResetTime > now ? usage.sessionResetTime : nil
            )
        )

        // The weekly window across all models.
        quotas.append(
            NotifyQuota(
                key: QuotaKey.weekly,
                label: "notify.window.weekly".localized,
                percentRemaining: remaining(from: usage.weeklyPercentage),
                resetsAt: usage.weeklyResetTime > now ? usage.weeklyResetTime : nil
            )
        )

        // Per-model weekly windows, for the providers that report them. Each is
        // included only when it is actually reporting: a model the account has
        // never used has no window, and a placeholder 100% would take a slot on
        // the tile away from a number the user needs.
        if descriptor.capabilities.perModelBreakdown {
            let weeklyReset = usage.weeklyResetTime > now ? usage.weeklyResetTime : nil

            appendModelWindow(
                to: &quotas,
                key: QuotaKey.opusWeekly,
                labelKey: "notify.window.opus",
                usedPercentage: usage.opusWeeklyPercentage,
                resetsAt: weeklyReset,
                now: now
            )
            appendModelWindow(
                to: &quotas,
                key: QuotaKey.sonnetWeekly,
                labelKey: "notify.window.sonnet",
                usedPercentage: usage.sonnetWeeklyPercentage,
                resetsAt: usage.sonnetWeeklyResetTime ?? weeklyReset,
                now: now
            )
            appendModelWindow(
                to: &quotas,
                key: QuotaKey.designWeekly,
                labelKey: "notify.window.design",
                usedPercentage: usage.designWeeklyPercentage,
                resetsAt: usage.designWeeklyResetTime ?? weeklyReset,
                now: now
            )
            appendModelWindow(
                to: &quotas,
                key: QuotaKey.fableWeekly,
                labelKey: "notify.window.fable",
                usedPercentage: usage.fableWeeklyPercentage,
                resetsAt: usage.fableWeeklyResetTime ?? weeklyReset,
                now: now
            )
        }

        // A spend allowance with a ceiling is a percentage like any other
        // window, so it draws a bar. Without a ceiling there is nothing to
        // divide by and it is not published at all: a bare "spent so far" number
        // answers no question the user is asking a Lock Screen.
        if let costUsed = usage.costUsed, let costLimit = usage.costLimit, costLimit > 0 {
            quotas.append(
                NotifyQuota(
                    key: QuotaKey.cost,
                    label: "notify.window.spend".localized,
                    percentRemaining: remaining(from: (costUsed / costLimit) * 100),
                    currencyCode: usage.costCurrency,
                    resetsAt: usage.weeklyResetTime > now ? usage.weeklyResetTime : nil
                )
            )
        }

        // Money with no ceiling: an overage grant and a prepaid credits balance
        // both publish their formatted balance and no ring, because there is no
        // percentage to draw one from.
        if let overage = usage.overageBalance {
            quotas.append(
                NotifyQuota(
                    key: QuotaKey.overage,
                    label: "notify.window.extra_usage".localized,
                    dollarRemaining: overage,
                    currencyCode: usage.overageBalanceCurrency
                )
            )
        }

        // An unlimited plan has no balance to report, and "unlimited" on a ring
        // is not a number, so the window is left out entirely.
        if descriptor.capabilities.credits,
           usage.creditsUnlimited != true,
           let credits = usage.creditsBalance {
            quotas.append(
                NotifyQuota(
                    key: QuotaKey.credits,
                    label: "notify.window.credits".localized,
                    dollarRemaining: credits,
                    currencyCode: "USD"
                )
            )
        }

        return quotas.map {
            NotifyQuotaReading(providerId: providerId, providerName: providerName, quota: $0)
        }
    }

    /// Stable keys for the gauge selection. Persisted in UserDefaults, so a
    /// value here must never be renamed: a user who picked "Opus 7d" for their
    /// Lock Screen would silently fall back to automatic if it were.
    enum QuotaKey {
        static let session = "session"
        static let weekly = "weekly"
        static let opusWeekly = "opus_weekly"
        static let sonnetWeekly = "sonnet_weekly"
        static let designWeekly = "design_weekly"
        static let fableWeekly = "fable_weekly"
        static let cost = "cost"
        static let overage = "overage"
        static let credits = "credits"
    }

    // MARK: - Helpers

    /// A per-model window, included only when the provider is reporting one.
    ///
    /// "Reporting" means either some of it has been used, or it carries a reset
    /// time of its own. A model with neither has no window on this account.
    private static func appendModelWindow(
        to quotas: inout [NotifyQuota],
        key: String,
        labelKey: String,
        usedPercentage: Double,
        resetsAt: Date?,
        now: Date
    ) {
        guard usedPercentage > 0 else { return }
        quotas.append(
            NotifyQuota(
                key: key,
                label: labelKey.localized,
                percentRemaining: remaining(from: usedPercentage),
                resetsAt: resetsAt.flatMap { $0 > now ? $0 : nil }
            )
        )
    }

    /// Used percent to remaining percent, clamped, because a provider that
    /// reports more than 100% used should read as an empty window rather than
    /// as a negative one.
    private static func remaining(from usedPercentage: Double) -> Double {
        guard usedPercentage.isFinite else { return 100 }
        return min(100, max(0, 100 - usedPercentage))
    }
}
