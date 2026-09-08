//
//  NotifyDeviceLink.swift
//  Claude Usage
//
//  The credentials that address one Notify! device, and what that device can show.
//

import Foundation

/// The credentials that let the app write to one Notify! device: the device
/// id and its per device token.
///
/// The settings pane asks for the two values separately, which is how the
/// Notify! app presents them. The app also offers a ready made notification URL
/// with both inside it, so `init?(pastedText:)` exists to take whatever the user
/// actually has on the clipboard: that full URL, or a bare `id token` pair.
struct NotifyDeviceLink: Sendable, Equatable, Hashable {
    /// Device id as the gateway spells it. iPhones and iPads use `IO` plus 14 or
    /// the legacy bare 8 characters, browsers `WB` plus 14, Macs `MC` plus 14,
    /// and groups `GRP` plus 5.
    let deviceId: String

    /// The per device secret. Never logged, and never written to UserDefaults:
    /// it lives in the Keychain.
    let token: String

    /// Which namespace the id belongs to, and therefore which surfaces this
    /// link can carry. A group, a Mac and a browser can all receive a Notify!
    /// notification, but none of them can show a Live Activity or a Lock Screen
    /// widget, so the app has to know the difference before it writes.
    var kind: NotifyDeviceKind {
        NotifyDeviceKind.kind(ofDeviceId: deviceId)
    }

    /// Whether a Live Activity can be started on this link at all. The gateway
    /// refuses a start aimed at a Mac or a browser, so this is checked before
    /// spending the request.
    var supportsLiveActivity: Bool {
        kind.supportsLiveActivity
    }

    /// Whether a widget written to this link would ever be drawn.
    var supportsWidget: Bool {
        kind.supportsWidget
    }

    /// Whether a Home Screen widget can be kept on this link.
    var supportsScreenWidget: Bool {
        kind.supportsScreenWidget
    }

    init?(deviceId: String, token: String) {
        let id = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDeviceId(id), !secret.isEmpty else { return nil }
        self.deviceId = id
        self.token = secret
    }

    /// Reads a link out of text the user pasted.
    ///
    /// Accepts a Notify! URL of any shape the gateway issues, including the
    /// `/notify/{id}?token=`, `/live-activity/{id}?token=` and
    /// `/widgets/{id}?token=` forms, and falls back to treating the text as an
    /// id and token separated by whitespace, a comma, or a colon.
    init?(pastedText: String) {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let link = Self.fromURL(text) {
            self = link
            return
        }

        let parts = text
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ":" })
            .map(String.init)
        guard parts.count == 2, let link = NotifyDeviceLink(deviceId: parts[0], token: parts[1]) else {
            return nil
        }
        self = link
    }

    /// Whether a string is shaped like a gateway id at all.
    ///
    /// Deliberately the gateway's own loose sanity check rather than its exact
    /// grammar, so an id from a namespace Notify! adds later still links. What
    /// the id can actually carry is `NotifyDeviceKind`'s job, not this one: a
    /// group or a Mac link is perfectly valid and simply cannot hold a Lock
    /// Screen surface, which is a thing to explain rather than a parse failure.
    ///
    /// Beyond the shape there is nothing to check locally. The gateway answers
    /// an unknown id and a wrong token with one identical response, on purpose.
    static func isValidDeviceId(_ value: String) -> Bool {
        let length = value.count
        guard length >= 8, length <= 32 else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The device id a pasted string names, whether or not a token came with it.
    ///
    /// A full link needs both halves, so `init?(pastedText:)` refuses a URL with
    /// no `?token=` on it. That shape is real: the gateway's own `/link`
    /// response hands back a `notification_url` with the token deliberately
    /// stripped. For a settings pane with a field per value, half an answer is
    /// still worth having, so this fills in the half that is there.
    static func deviceId(inPastedText text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let identifier = identifier(inURL: text), isValidDeviceId(identifier) {
            return identifier
        }

        let parts = text
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ":" })
            .map(String.init)
        guard let first = parts.first, isValidDeviceId(first) else { return nil }
        return first
    }

    /// The last non empty path segment of a URL, which is where every gateway
    /// route that carries an id puts it.
    private static func identifier(inURL text: String) -> String? {
        guard let components = URLComponents(string: text), components.host != nil else {
            return nil
        }
        return components.path
            .split(separator: "/")
            .map(String.init)
            .last { !$0.isEmpty }
    }

    private static func fromURL(_ text: String) -> NotifyDeviceLink? {
        guard let components = URLComponents(string: text), components.host != nil else {
            return nil
        }
        let token = components.queryItems?.first { $0.name == "token" }?.value ?? ""
        return NotifyDeviceLink(deviceId: identifier(inURL: text) ?? "", token: token)
    }
}

/// Which kind of Notify! identity an id names, and therefore what this app can
/// put on it.
///
/// Notify! mints ids in several namespaces, fenced against each other, and they
/// are not interchangeable destinations. A Live Activity is
/// gated by the gateway itself: a start aimed at a Mac of either generation or
/// at a web push browser is refused outright, with the reason given as "the
/// target device cannot show Live Activities at all". Widgets carry no such
/// gate, but the only thing that renders one is the iOS widget extension, so a
/// widget written to a Mac or a browser is a row nothing will ever draw.
///
/// The two surfaces are gated differently, and only one of them is gated by the
/// namespace at all. A Live Activity is refused for a Mac or a browser. A widget
/// is not: the gateway is explicit that there is no device-type gate on widgets
/// and that legacy, `WB` and `MC` devices alike can own one, so this app does
/// not invent a rule the service does not have. A group is the exception to
/// both, being a fan-out target rather than a device, with no surface of its own.
///
/// Note which way round that is. The three that cannot are named, and everything
/// else is allowed, rather than the other way about. App device ids are not one
/// fixed shape: the legacy format is 8 characters, the newer iOS namespace is
/// `IO` plus 14, and more will follow. Listing what may pass would refuse a real
/// phone the day Notify! mints a format this file has never heard of, and a
/// refused phone looks like the app being broken.
enum NotifyDeviceKind: Sendable, Equatable, Hashable, CaseIterable {
    /// An iPhone or iPad: the `IO` plus 14 namespace, or the legacy 8 character
    /// format that iOS and older Mac listeners share.
    ///
    /// A legacy id cannot be told apart locally from an older poll only Mac
    /// listener, which uses the same 8 characters and cannot show a Live
    /// Activity either, so the gateway has the last word on those. An `IO` id
    /// carries no such ambiguity.
    case appDevice

    /// A push capable Mac listener, `MC` plus 14 characters.
    case mac

    /// A web push browser, `WB` plus 14 characters.
    case web

    /// A notification group, `GRP` plus 5 characters. Not a device at all: it
    /// fans a notification out to its members, and owns no surface of its own.
    case group

    /// A well formed id in none of the namespaces named here, which includes any
    /// app device format added after this was written. Allowed through with both
    /// surfaces rather than refused: the gateway is the only place that can
    /// decide, and refusing by default would break every new format on the day
    /// it ships. It differs from `appDevice` only in what the pane calls it,
    /// since claiming an unknown id is an iPhone would be a guess.
    case unrecognized

    /// Classifies an id by the namespace it belongs to.
    ///
    /// The grammars are the gateway's own: `GRP[A-Z0-9]{5}`, `WB[A-Z0-9]{14}`,
    /// `MC[A-Z0-9]{14}`, `IO[A-Z0-9]{14}`, and the legacy `[A-Za-z0-9]{8}`.
    /// The legacy form is deliberately case insensitive: iOS mints uppercase,
    /// but older Mac listeners minted mixed case, so lowercase legacy ids exist.
    ///
    /// Note that `GRP` plus 5 is eight characters, exactly the length of a
    /// legacy id, so the two grammars genuinely overlap and something has to
    /// break the tie. The group prefix is tested first, which is the same tie
    /// break the gateway itself makes: anything beginning with `GRP` is routed
    /// to the group fan out and everything else is treated as a device.
    static func kind(ofDeviceId deviceId: String) -> NotifyDeviceKind {
        func hasPrefix(_ prefix: String, thenDigits count: Int) -> Bool {
            guard deviceId.count == prefix.count + count, deviceId.hasPrefix(prefix) else {
                return false
            }
            return deviceId.dropFirst(prefix.count).allSatisfy { character in
                character.isASCII && (character.isNumber || (character.isLetter && character.isUppercase))
            }
        }

        // The three that cannot show a surface are matched first and matched
        // exactly, prefix and length together. Prefix alone would refuse a
        // legacy id that merely happens to spell "MC" in its first two
        // characters, and refusing a working phone is the expensive mistake here.
        if hasPrefix("GRP", thenDigits: 5) { return .group }
        if hasPrefix("WB", thenDigits: 14) { return .web }
        if hasPrefix("MC", thenDigits: 14) { return .mac }

        // The newer iOS namespace, and then the legacy format.
        if hasPrefix("IO", thenDigits: 14) { return .appDevice }
        if deviceId.count == 8, deviceId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return .appDevice
        }

        // Anything else is a device this file has not been taught to name, not a
        // device that cannot show anything.
        return .unrecognized
    }

    /// Whether a Live Activity can be started on this kind of id at all.
    ///
    /// The gateway refuses a start for a Mac or a browser with a 400, so asking
    /// is not merely useless, it burns a request and reads to the user as a
    /// failure of the app's.
    var supportsLiveActivity: Bool {
        switch self {
        case .appDevice, .unrecognized: return true
        case .mac, .web, .group: return false
        }
    }

    /// Whether a widget can be kept here.
    ///
    /// Everything except a group. The gateway says plainly that widgets carry no
    /// device-type gate and that legacy, `WB` and `MC` devices can all own one,
    /// so which of them actually draws it is Notify!'s business rather than a
    /// rule for this app to invent. A group is excluded because it is not a
    /// device: it fans a notification out to its members and owns nothing.
    var supportsWidget: Bool {
        switch self {
        case .appDevice, .unrecognized, .mac, .web: return true
        case .group: return false
        }
    }

    /// Whether a Home Screen widget can be kept here.
    ///
    /// The same answer as the Lock Screen widget and for the same reason: the
    /// gateway states that screen widgets carry no device-type gate and that
    /// legacy, `IO`, `WB` and `MC` ids can all own one. Only a group is
    /// excluded, having no widget list of its own to write to.
    var supportsScreenWidget: Bool {
        supportsWidget
    }

    /// Whether any surface at all is available here.
    var supportsAnySurface: Bool {
        supportsLiveActivity || supportsWidget || supportsScreenWidget
    }

    /// What to call this in the settings pane.
    var displayName: String {
        switch self {
        case .appDevice: return "notify.device_kind.app_device".localized
        case .mac: return "notify.device_kind.mac".localized
        case .web: return "notify.device_kind.web".localized
        case .group: return "notify.device_kind.group".localized
        case .unrecognized: return "notify.device_kind.unknown".localized
        }
    }

    /// One sentence naming why a Live Activity cannot be shown here, or nil when
    /// it can. Written for the person who has just entered an ID and needs to
    /// know what to use instead.
    var liveActivityUnsupportedReason: String? {
        switch self {
        case .appDevice, .unrecognized:
            return nil
        case .mac:
            return "notify.unsupported.live_activity_mac".localized
        case .web:
            return "notify.unsupported.live_activity_web".localized
        case .group:
            return Self.groupReason
        }
    }

    /// The Home Screen widget shares the Lock Screen widget's answer.
    var screenWidgetUnsupportedReason: String? {
        widgetUnsupportedReason
    }

    /// The same for the widget, which only a group cannot keep.
    var widgetUnsupportedReason: String? {
        switch self {
        case .appDevice, .unrecognized, .mac, .web:
            return nil
        case .group:
            return Self.groupReason
        }
    }

    private static var groupReason: String {
        "notify.unsupported.group".localized
    }

}

/// What the gateway knows about a device, as reported by a credential check.
/// `name` is never empty: the gateway synthesizes one from the platform when
/// the device has no user chosen name.
struct NotifyDeviceInfo: Sendable, Equatable {
    let deviceId: String
    let name: String
    let platform: String?

    init(deviceId: String, name: String, platform: String? = nil) {
        self.deviceId = deviceId
        self.name = name
        self.platform = platform
    }

    /// One line description for the settings pane, e.g. "Apollo (iOS)".
    var displayDescription: String {
        guard let platform, !platform.isEmpty else { return name }
        return "\(name) (\(platform))"
    }
}
