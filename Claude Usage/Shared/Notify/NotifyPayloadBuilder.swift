//
//  NotifyPayloadBuilder.swift
//  Claude Usage
//
//  Turns quota readings into the tile and gauge published to Notify!.
//

import Foundation

/// Turns quota readings into the tile and gauge published to Notify!.
///
/// This is the whole decision layer of the feature and it is deliberately pure:
/// no clock of its own, no network, no settings lookups. What to show, in what
/// order, in what words, and in what color is decided here so it can be tested
/// as plain state assertions.
///
/// The rules:
/// 1. The worst quota leads. Readings sort by status severity, then by how
///    little is left, so the number that needs attention is the headline and
///    the tile takes its color and progress bar from it.
/// 2. The tile carries up to six windows as a metrics row, because six is the
///    gateway's ceiling and more than six is unreadable on a Lock Screen.
/// 3. Labels drop the provider name when every reading comes from the same
///    provider, so a single provider tile reads "5h  7d" rather than
///    "Claude 5h  Claude 7d".
/// 4. Percentages are remaining, not used. Every surface in this app reads that
///    way, and a full bar meaning a full quota is the only intuitive mapping
///    for a gauge.
struct NotifyPayloadBuilder: Sendable {
    /// The tile and widget title. Both name the sending app rather than the
    /// current quota: the gateway treats a title as an identity, and a widget
    /// that renamed itself whenever the user switched provider would be
    /// unrecognizable in the phone's widget picker.
    static let defaultTitle = "Claude Usage"

    private let title: String

    init(title: String = NotifyPayloadBuilder.defaultTitle) {
        self.title = title
    }

    func payload(
        readings: [NotifyQuotaReading],
        gaugeSelection: NotifyGaugeSelection = .automatic,
        includesTile: Bool = true,
        includesGauge: Bool = true,
        includesScreenTile: Bool = true,
        now: Date = Date()
    ) -> NotifyPayload {
        let ordered = Self.ordered(readings)
        guard let headline = ordered.first else { return .empty }

        // The Live Activity and the Home Screen tile are built once and shared.
        // The gateway takes the same body on both routes, so building them twice
        // could only produce two things that were supposed to be identical and
        // one day were not.
        let tile = (includesTile || includesScreenTile)
            ? self.tile(ordered: ordered, headline: headline, now: now)
            : nil

        return NotifyPayload(
            tile: includesTile ? tile : nil,
            gauge: includesGauge
                ? gauge(ordered: ordered, headline: headline, selection: gaugeSelection, now: now)
                : nil,
            screenTile: includesScreenTile ? tile : nil
        )
    }

    // MARK: - Ordering

    /// Worst first, and fully deterministic: two payloads built from the same
    /// readings must compare equal, or the driver would republish forever.
    static func ordered(_ readings: [NotifyQuotaReading]) -> [NotifyQuotaReading] {
        readings.sorted { left, right in
            let leftStatus = left.quota.status
            let rightStatus = right.quota.status
            if leftStatus != rightStatus { return leftStatus > rightStatus }
            if left.quota.sortablePercentRemaining != right.quota.sortablePercentRemaining {
                return left.quota.sortablePercentRemaining < right.quota.sortablePercentRemaining
            }
            if left.providerName != right.providerName { return left.providerName < right.providerName }
            if left.quota.key != right.quota.key { return left.quota.key < right.quota.key }
            // The last tie break, and the one that makes the comparator total.
            // Display names are not unique, and Swift's sort is not stable, so
            // without this two readings that tie on everything else could come
            // back in either order. The payload would then differ between builds
            // of the same state and the driver would republish for nothing.
            return left.providerId < right.providerId
        }
    }

    // MARK: - Tile

    private func tile(
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        now: Date
    ) -> NotifyTile? {
        let omitsProviderName = Set(ordered.map { $0.providerId }).count == 1
        let metrics = ordered
            .prefix(NotifyLimits.metricCount)
            .compactMap { reading in
                NotifyMetric(
                    label: Self.label(for: reading, omittingProviderName: omitsProviderName),
                    value: Self.headlineValue(for: reading.quota),
                    unit: Self.unit(for: reading.quota),
                    tintHex: reading.quota.status.notifyTintHex
                )
            }

        return NotifyTile(
            title: title,
            body: Self.summary(for: headline, now: now),
            symbolName: NotifySymbol.quota,
            tintHex: headline.quota.status.notifyTintHex,
            progress: Self.progress(for: ordered),
            trailing: headline.quota.compactResetTime(now: now),
            metrics: metrics
        )
    }

    // MARK: - Gauge

    private func gauge(
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        selection: NotifyGaugeSelection,
        now: Date
    ) -> NotifyGauge? {
        let shown = Self.selected(from: ordered, selection: selection) ?? headline

        return NotifyGauge(
            title: title,
            value: Self.headlineValue(for: shown.quota),
            unit: Self.unit(for: shown.quota),
            detail: Self.gaugeDetail(for: shown, now: now),
            symbolName: NotifySymbol.quota,
            tintHex: shown.quota.status.notifyTintHex,
            progress: shown.quota.percentRemaining
        )
    }

    /// The reading the user asked the gauge to show, or nil when the selection
    /// is automatic or names a window that is no longer reporting.
    static func selected(
        from readings: [NotifyQuotaReading],
        selection: NotifyGaugeSelection
    ) -> NotifyQuotaReading? {
        guard !selection.isAutomatic else { return nil }
        return readings.first {
            $0.providerId == selection.providerId && $0.quota.key == selection.quotaKey
        }
    }

    // MARK: - Words and numbers

    /// "Claude 5h", or just "5h" when the tile only covers one provider.
    static func label(for reading: NotifyQuotaReading, omittingProviderName: Bool) -> String {
        guard !omittingProviderName else { return reading.quota.label }
        return "\(reading.providerName) \(reading.quota.label)"
    }

    /// A percentage as a bare integer, or the formatted balance for a quota
    /// measured in money rather than percent.
    static func headlineValue(for quota: NotifyQuota) -> String {
        if let balance = quota.formattedDollarRemaining { return balance }
        return "\(Int((quota.percentRemaining ?? 0).rounded()))"
    }

    static func unit(for quota: NotifyQuota) -> String? {
        quota.isDollarBased ? nil : "%"
    }

    /// "Claude 5h, 42% left, resets in 2:14". The tile's body line, which the
    /// gateway shows only when there are no metrics to put in its place, so it
    /// has to carry the number itself.
    static func summary(for reading: NotifyQuotaReading, now: Date) -> String {
        var parts = ["\(reading.providerName) \(reading.quota.label)"]

        if let balance = reading.quota.formattedDollarRemaining {
            parts.append("notify.summary.balance_left".localized(with: balance))
        } else {
            let percent = Int((reading.quota.percentRemaining ?? 0).rounded())
            parts.append("notify.summary.percent_left".localized(with: percent))
        }

        if let resets = reading.quota.compactResetTime(now: now) {
            parts.append(
                resets == "soon"
                    ? "notify.summary.resets_soon".localized
                    : "notify.summary.resets_in".localized(with: resets)
            )
        }

        return parts.joined(separator: ", ")
    }

    /// "Claude 5h, resets in 2:14". The widget's quieter line, which sits next
    /// to a headline value that already shows the percentage, so repeating it
    /// here would waste the one short line the widget has.
    static func gaugeDetail(for reading: NotifyQuotaReading, now: Date) -> String {
        var parts = ["\(reading.providerName) \(reading.quota.label)"]

        if let resets = reading.quota.compactResetTime(now: now) {
            parts.append(
                resets == "soon"
                    ? "notify.summary.resets_soon".localized
                    : "notify.summary.resets_in".localized(with: resets)
            )
        }

        return parts.joined(separator: ", ")
    }

    /// The bar on the tile. Money-based quotas have no percentage to draw, so
    /// the bar falls through to the worst quota that does have one rather than
    /// disappearing whenever a credit balance happens to be the headline.
    static func progress(for ordered: [NotifyQuotaReading]) -> Double? {
        ordered.first { $0.quota.percentRemaining != nil }?.quota.percentRemaining
    }
}
