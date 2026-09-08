//
//  NotifyPayload.swift
//  Claude Usage
//
//  Everything the app wants standing on the phone right now.
//

import Foundation

/// Which quota the Lock Screen widget gauge shows.
///
/// Both fields empty means "whichever quota needs attention most", which is the
/// useful default for a glance and the only sane behavior before the user has
/// chosen anything.
struct NotifyGaugeSelection: Sendable, Equatable {
    let providerId: String
    let quotaKey: String

    init(providerId: String = "", quotaKey: String = "") {
        self.providerId = providerId
        self.quotaKey = quotaKey
    }

    /// Whether the selection names a specific window.
    var isAutomatic: Bool {
        providerId.isEmpty || quotaKey.isEmpty
    }

    static let automatic = NotifyGaugeSelection()
}

/// Everything the app wants standing on the phone right now.
///
/// `Equatable` on purpose: the publish gate drops a payload identical to the
/// last one, so an unchanged quota costs no HTTP at all. A nil surface means
/// the user turned that surface off, and the driver leaves it alone rather
/// than clearing it.
struct NotifyPayload: Sendable, Equatable {
    let tile: NotifyTile?
    let gauge: NotifyGauge?

    /// The Home Screen tile. Deliberately the same `NotifyTile` the Live
    /// Activity carries, because the gateway derives both content sets from one
    /// module: any body that starts a Live Activity is a valid screen widget
    /// body. It is a separate property rather than a reuse of `tile` because
    /// the two surfaces are switched on and off independently and published on
    /// different clocks, so a payload has to be able to carry one without the
    /// other.
    let screenTile: NotifyTile?

    init(
        tile: NotifyTile? = nil,
        gauge: NotifyGauge? = nil,
        screenTile: NotifyTile? = nil
    ) {
        self.tile = tile
        self.gauge = gauge
        self.screenTile = screenTile
    }

    /// Nothing to say, so nothing to send.
    var isEmpty: Bool {
        tile == nil && gauge == nil && screenTile == nil
    }

    static let empty = NotifyPayload()
}
