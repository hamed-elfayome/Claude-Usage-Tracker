//
//  NotifyPublishError.swift
//  Claude Usage
//
//  Why a publish to Notify! did not land, and the remedy each failure implies.
//

import Foundation

/// Why a publish to Notify! did not land.
///
/// A dedicated type rather than an `AppError` case: every message here is shown
/// in the Notify! pane, and half of them name an action only the user can take
/// on their phone. `AppError` speaks about fetching usage from a provider,
/// which is the opposite direction of travel.
///
/// The gateway answers a missing token, a wrong token, an unknown device and
/// somebody else's device with one identical 403 so that it never confirms an
/// id exists, so `rejectedCredentials` deliberately covers all four.
enum NotifyPublishError: Error, Sendable, Equatable, LocalizedError {
    /// No device id and token saved yet.
    case notLinked

    /// The gateway refused the credentials, or the device is not ours.
    case rejectedCredentials

    /// The device cannot show a Live Activity yet. Carries the gateway's own
    /// explanation, which distinguishes "the app has never been opened" from
    /// "Live Activities are switched off" from "several tiles are live".
    case liveActivityUnavailable(String)

    /// The tile was dismissed by the user or has already ended, so it can never
    /// be updated again. The driver forgets the handle and starts a fresh tile.
    case tileGone

    /// Push to start backoff after tiles that Apple accepted but never
    /// delivered. The ladder is 30 minutes after 2, 3 hours after 4, 6 hours
    /// after 6, and it resets the moment a tile appears.
    case backoff(retryAfter: TimeInterval, openingTheAppMayHelp: Bool)

    /// The gateway named a field it would not accept, or a per device ceiling
    /// was reached (5 live tiles, 10 widgets).
    case invalidPayload(String)

    /// A start where Apple never answered. A tile may exist, so the handle is
    /// kept and polled rather than started again, which could leave two tiles.
    case deliveryUnconfirmed(activityId: String?)

    /// The request never completed.
    case transportFailed(String)

    /// The gateway has this surface switched off server side. Home Screen
    /// widgets ship behind a kill switch, so a build that supports them can meet
    /// a service that is not serving them yet. Reads and deletes stay open, only
    /// creates and updates are refused, and the remedy is to wait rather than to
    /// change anything.
    case surfaceSwitchedOff(String)

    case unexpectedStatus(Int)

    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notLinked:
            return "notify.error.not_linked".localized
        case .rejectedCredentials:
            return "notify.error.rejected_credentials".localized
        case .liveActivityUnavailable(let reason):
            return reason.isEmpty ? "notify.error.live_activity_unavailable".localized : reason
        case .tileGone:
            return "notify.error.tile_gone".localized
        case .backoff(let retryAfter, let openingTheAppMayHelp):
            let wait = Self.minutes(retryAfter)
            return openingTheAppMayHelp
                ? "notify.error.backoff_open_app".localized(with: wait)
                : "notify.error.backoff".localized(with: wait)
        case .invalidPayload(let message):
            return message.isEmpty ? "notify.error.invalid_payload".localized : message
        case .deliveryUnconfirmed:
            return "notify.error.delivery_unconfirmed".localized
        case .transportFailed(let message):
            return "notify.error.transport_failed".localized(with: message)
        case .surfaceSwitchedOff(let message):
            return message.isEmpty ? "notify.error.surface_switched_off".localized : message
        case .unexpectedStatus(let code):
            return "notify.error.unexpected_status".localized(with: code)
        case .malformedResponse:
            return "notify.error.malformed_response".localized
        }
    }

    /// How long to wait before trying again, when waiting is the remedy.
    var retryAfter: TimeInterval? {
        switch self {
        case .backoff(let retryAfter, _): return retryAfter
        default: return nil
        }
    }

    /// Whether retrying the same request unchanged could ever succeed. Used to
    /// decide between backing off and giving up until something changes.
    var isRetryable: Bool {
        switch self {
        case .transportFailed, .backoff, .deliveryUnconfirmed, .unexpectedStatus, .surfaceSwitchedOff:
            return true
        case .notLinked, .rejectedCredentials, .liveActivityUnavailable, .tileGone,
             .invalidPayload, .malformedResponse:
            return false
        }
    }

    /// A wait as a phrase a person reads, for example "30 minutes" or "an hour".
    static func minutes(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        if minutes <= 1 { return "notify.wait.a_minute".localized }
        if minutes < 60 { return "notify.wait.minutes".localized(with: minutes) }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? "notify.wait.an_hour".localized : "notify.wait.hours".localized(with: hours)
    }
}
