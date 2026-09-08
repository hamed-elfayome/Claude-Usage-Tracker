//
//  NotifyPublishing.swift
//  Claude Usage
//
//  What the app can ask of Notify!, in value types, with no idea HTTP exists.
//

import Foundation

/// Publishing quota state to a linked Notify! device.
///
/// The abstract side of the feature: what the app can ask for, in plain value
/// types. `NotifyGatewayClient` is the implementation, and it is the only file
/// that knows about URLs. A protocol so tests can drive the driver with a stub
/// and no network.
///
/// All three write methods take the handle of the thing they last wrote and
/// return the handle to store next time. That is what keeps the app from
/// touching a tile or widget the user created for something else: a nil handle
/// means "create your own", and every later write addresses that one by id.
protocol NotifyPublishing: Sendable {
    /// Starts a Live Activity, or updates the one `activityId` names.
    /// - Returns: the activity id to store for the next update.
    func publishTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        activityId: String?
    ) async throws -> String

    /// Creates the Lock Screen widget, or updates the one `widgetId` names.
    /// - Returns: the widget id to store for the next update.
    func publishGauge(
        _ gauge: NotifyGauge,
        link: NotifyDeviceLink,
        widgetId: String?
    ) async throws -> String

    /// Creates the Home Screen widget, or updates the one `screenWidgetId`
    /// names.
    ///
    /// Takes a `NotifyTile` rather than a shape of its own: the gateway derives
    /// this route's content contract from the Live Activity module, so the two
    /// surfaces genuinely accept one body.
    /// - Returns: the screen widget id to store for the next update.
    func publishScreenTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        screenWidgetId: String?
    ) async throws -> String

    /// Ends the Live Activity, optionally leaving it on the Lock Screen for a
    /// while so the final state can be read.
    func endTile(link: NotifyDeviceLink, activityId: String, keepFor: TimeInterval) async throws

    /// Checks a device id and token pair and describes the device it names.
    /// The only user-triggered call, and rate limited to five a minute by the
    /// gateway, so it belongs behind an explicit button and nothing else.
    func deviceInfo(link: NotifyDeviceLink) async throws -> NotifyDeviceInfo
}
