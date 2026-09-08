//
//  NotifyQuota.swift
//  Claude Usage
//
//  One quota window, flattened into the shape the payload builder needs.
//

import Foundation

/// How much attention a quota window needs.
///
/// Four levels rather than the app's three, because a depleted window deserves
/// its own color on a Lock Screen: "you have run out" and "you are nearly out"
/// are different messages, and on a ring a quarter of a degree apart they are
/// otherwise indistinguishable. The first three thresholds are the same ones
/// `UsageStatusCalculator` uses in remaining mode, so a window that reads
/// critical in the menu bar reads critical on the phone.
enum NotifyQuotaStatus: Int, Sendable, Comparable, CaseIterable {
    case healthy = 0
    case warning = 1
    case critical = 2
    case depleted = 3

    static func < (lhs: NotifyQuotaStatus, rhs: NotifyQuotaStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The status for a percentage of quota remaining.
    static func forRemaining(_ percentRemaining: Double) -> NotifyQuotaStatus {
        if percentRemaining <= 0 { return .depleted }
        if percentRemaining < 10 { return .critical }
        if percentRemaining < 30 { return .warning }
        return .healthy
    }
}

/// One quota window the app is currently reporting.
///
/// Deliberately a flat value rather than a view onto `ClaudeUsage`: the payload
/// builder is pure and testable only if what it takes carries no behavior of
/// its own. `NotifyUsageReadings` is the one place that knows how to turn a
/// `ClaudeUsage` into these.
///
/// Percentages here are always **remaining**, not used. Every surface in this
/// app reads that way, and a full bar meaning a full quota is the only
/// intuitive mapping a gauge has.
struct NotifyQuota: Sendable, Equatable {
    /// Stable key for this window, used by the gauge selection so a user's
    /// choice survives a restart. Never localized and never renamed.
    let key: String

    /// Short label for the window, for example "5h" or "Opus 7d".
    let label: String

    /// Percent of the window still available, 0 to 100. Nil for a quota
    /// measured in money with no limit to divide by.
    let percentRemaining: Double?

    /// Money still available, for a credit balance or a spend allowance.
    let dollarRemaining: Double?

    /// ISO code for `dollarRemaining`, for example "USD".
    let currencyCode: String?

    /// When the window rolls over, when it rolls over at all. A credit balance
    /// normally has no reset.
    let resetsAt: Date?

    init(
        key: String,
        label: String,
        percentRemaining: Double? = nil,
        dollarRemaining: Double? = nil,
        currencyCode: String? = nil,
        resetsAt: Date? = nil
    ) {
        self.key = key
        self.label = label
        self.percentRemaining = percentRemaining
        self.dollarRemaining = dollarRemaining
        self.currencyCode = currencyCode
        self.resetsAt = resetsAt
    }

    /// Whether this window is measured in money rather than in percent. A
    /// dollar quota has no ring to draw, which is why the tile's bar falls
    /// through to the worst window that does have one.
    var isDollarBased: Bool {
        percentRemaining == nil && dollarRemaining != nil
    }

    /// How much attention this window needs.
    ///
    /// A money quota with no percentage has only one thing to go on: whether
    /// there is anything left at all.
    var status: NotifyQuotaStatus {
        if let percentRemaining {
            return .forRemaining(percentRemaining)
        }
        if let dollarRemaining {
            return dollarRemaining > 0 ? .healthy : .depleted
        }
        return .healthy
    }

    /// Percent remaining for ordering, treating a money quota as full so a
    /// healthy credit balance never sorts above a window that is actually low.
    var sortablePercentRemaining: Double {
        percentRemaining ?? 100
    }

    /// The formatted balance for a money quota, or nil when this window is
    /// measured in percent.
    var formattedDollarRemaining: String? {
        guard let dollarRemaining, percentRemaining == nil else { return nil }
        return Self.formatCurrency(dollarRemaining, code: currencyCode)
    }

    /// A compact countdown to the reset: "3d", "4:40", "12m", or "soon".
    ///
    /// Takes `now` rather than reading the clock so the payload it ends up in
    /// is a pure function of its inputs, which is what makes the builder
    /// testable and the publish gate's dedupe meaningful.
    func compactResetTime(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return "soon" }
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600 { return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60) }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "soon"
    }

    /// Money as the widget wants it: short, and never more precise than it
    /// needs to be. A whole balance drops its cents, because the widget has
    /// forty characters and "$120" reads faster than "$120.00".
    ///
    /// Formatted in the user's own locale rather than a fixed one. The phone
    /// only renders the string it is handed, so this Mac is the only place that
    /// knows how the person reading it expects money to look.
    static func formatCurrency(
        _ amount: Double,
        code: String?,
        locale: Locale = .current
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code ?? "USD"
        let isWhole = amount == amount.rounded()
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

/// One provider's quota window, paired with the provider's display name.
///
/// The driver reads these off the active profile's usage; the payload builder
/// needs the name for a metric label and must not reach back into the app's
/// models to find one.
struct NotifyQuotaReading: Sendable, Equatable {
    let providerId: String
    let providerName: String
    let quota: NotifyQuota

    init(providerId: String, providerName: String, quota: NotifyQuota) {
        self.providerId = providerId
        self.providerName = providerName
        self.quota = quota
    }
}
