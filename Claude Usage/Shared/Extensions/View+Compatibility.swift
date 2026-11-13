//
//  View+Compatibility.swift
//  Claude Usage
//
//  SwiftUI shims that let the app run on macOS 13 (Ventura) while still using
//  the macOS 14 APIs where they exist.
//
//  Remove these wrappers (and call the SwiftUI APIs directly) whenever the
//  deployment target is raised to macOS 14 or later.
//

import SwiftUI

extension View {
    /// Runs `action` with the new value whenever `value` changes.
    ///
    /// Bridges `onChange(of:_:)` (macOS 14+) and the deprecated
    /// `onChange(of:perform:)` (macOS 13). Only the new value is forwarded because
    /// the macOS 13 API doesn't provide the old one.
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        _ action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// Hides the system focus ring on macOS 14+. macOS 13 has no equivalent API, so
    /// the ring is left as the system draws it.
    @ViewBuilder
    func focusEffectDisabledCompat() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }

    /// Pulses an SF Symbol while `isActive` is true (macOS 14+). On macOS 13 the symbol
    /// is shown statically; its tint color still conveys the state.
    @ViewBuilder
    func symbolPulseCompat(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.pulse, isActive: isActive)
        } else {
            self
        }
    }

    /// Animates SF Symbol swaps with the replace effect (macOS 14+). On macOS 13 the
    /// symbol changes without a transition.
    @ViewBuilder
    func symbolReplaceTransitionCompat() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}
