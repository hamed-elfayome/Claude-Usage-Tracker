//
//  NotifyGauge.swift
//  Claude Usage
//
//  The content of the Lock Screen widget published to Notify!.
//

import Foundation

/// The content of the Notify! widget the app keeps on the Lock Screen.
///
/// `progress` is the gauge: the gateway draws it as a bar on the rectangular
/// widget and as a ring on the circular one, which is the whole reason a quota
/// belongs here. The headline `value` is display text the caller formats, so
/// the phone never does arithmetic on it.
struct NotifyGauge: Sendable, Equatable {
    /// The widget's identity in the phone's widget picker. Stable on purpose:
    /// a title that changed with the selected quota would rename the widget
    /// under the user every time they switched.
    let title: String

    /// Pre-formatted headline, for example "42".
    let value: String?

    /// Small label beside the value, for example "%".
    let unit: String?

    /// Quieter second line, for example "Claude 5h, resets in 2:14".
    let detail: String?

    /// SF Symbol drawn as the widget icon.
    let symbolName: String?

    /// Accent color as `#RRGGBB`, normally the shown quota's status.
    let tintHex: String?

    /// The gauge, 0 to 100. We send quota remaining here.
    let progress: Double?

    init?(
        title: String,
        value: String? = nil,
        unit: String? = nil,
        detail: String? = nil,
        symbolName: String? = nil,
        tintHex: String? = nil,
        progress: Double? = nil
    ) {
        guard let title = NotifyLimits.text(title, maximum: NotifyLimits.widgetTitleLength) else {
            return nil
        }
        self.title = title
        self.value = NotifyLimits.text(value, maximum: NotifyLimits.widgetValueLength)
        self.unit = NotifyLimits.text(unit, maximum: NotifyLimits.widgetUnitLength)
        self.detail = NotifyLimits.text(detail, maximum: NotifyLimits.widgetDetailLength)
        self.symbolName = NotifyLimits.text(symbolName, maximum: NotifyLimits.symbolLength)
        self.tintHex = NotifyLimits.tint(tintHex)
        self.progress = NotifyLimits.progress(progress)
    }
}
