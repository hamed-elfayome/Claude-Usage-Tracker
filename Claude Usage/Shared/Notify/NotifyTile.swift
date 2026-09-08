//
//  NotifyTile.swift
//  Claude Usage
//
//  The content of the Live Activity tile published to Notify!.
//

import Foundation

/// One cell of a Live Activity metrics row, for example "5h 42%".
///
/// The gateway renders up to six of these side by side where the tile's body
/// line would otherwise go, which is what makes a metrics tile the right shape
/// for several quota windows at once.
struct NotifyMetric: Sendable, Equatable, Hashable {
    let label: String
    let value: String
    let unit: String?
    let tintHex: String?

    /// Fails only when the label or value is empty after cleaning, because the
    /// gateway requires both. Everything else shortens or drops.
    init?(label: String, value: String, unit: String? = nil, tintHex: String? = nil) {
        guard let label = NotifyLimits.text(label, maximum: NotifyLimits.metricLabelLength),
              let value = NotifyLimits.text(value, maximum: NotifyLimits.metricValueLength) else {
            return nil
        }
        self.label = label
        self.value = value
        self.unit = NotifyLimits.text(unit, maximum: NotifyLimits.metricUnitLength)
        self.tintHex = NotifyLimits.tint(tintHex)
    }
}

/// The content of the Live Activity tile the app keeps on the Lock Screen.
///
/// The gateway has no notion of a tile type: the fields present decide how the
/// tile draws, so a title plus a progress bar plus a metrics row IS the metrics
/// layout. Every field is normalized on the way in, so a tile that exists is a
/// tile the gateway will accept.
///
/// The Home Screen widget carries this same value. The gateway derives that
/// route's content contract from the Live Activity's, field for field and cap
/// for cap, so building a second shape for it could only produce two pictures
/// of one quota that were meant to be identical.
struct NotifyTile: Sendable, Equatable {
    /// The tile's identity, and the one field a start cannot omit.
    let title: String

    /// Second line, shown only when there are no metrics to put there.
    let body: String?

    /// SF Symbol drawn as the tile icon.
    let symbolName: String?

    /// Accent color as `#RRGGBB`, normally the worst quota status on show.
    let tintHex: String?

    /// The progress bar, 0 to 100. We send quota remaining here, so a full bar
    /// means a full quota.
    let progress: Double?

    /// Static text where a timer would sit, normally the headline window's
    /// compact reset countdown.
    let trailing: String?

    /// Up to six values rendered side by side. Longer input is truncated to the
    /// first six rather than rejected.
    let metrics: [NotifyMetric]

    init?(
        title: String,
        body: String? = nil,
        symbolName: String? = nil,
        tintHex: String? = nil,
        progress: Double? = nil,
        trailing: String? = nil,
        metrics: [NotifyMetric] = []
    ) {
        guard let title = NotifyLimits.text(title, maximum: NotifyLimits.titleLength) else {
            return nil
        }
        self.title = title
        self.body = NotifyLimits.text(body, maximum: NotifyLimits.bodyLength)
        self.symbolName = NotifyLimits.text(symbolName, maximum: NotifyLimits.symbolLength)
        self.tintHex = NotifyLimits.tint(tintHex)
        self.progress = NotifyLimits.progress(progress)
        self.trailing = NotifyLimits.text(trailing, maximum: NotifyLimits.trailingLength)
        self.metrics = Array(metrics.prefix(NotifyLimits.metricCount))
    }
}
