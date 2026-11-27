//
//  Provider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// Stable identity for a usage provider. The raw value is persisted in
/// `profiles_v3` — never rename a case's raw value.
///
/// Adding a provider: see docs/ADDING_A_PROVIDER.md.
enum Provider: String, Codable, CaseIterable, Equatable {
    case anthropic
    case codex
    case antigravity

    var descriptor: ProviderDescriptor {
        ProviderRegistry.descriptor(for: self)
    }
}

/// Antigravity quota pool a profile shows. `agy` reports two pools that each
/// have their own limits; the app shows one session + one weekly bar per
/// profile, so each Antigravity profile picks one. Raw values are persisted.
enum AntigravityPool: String, Codable, CaseIterable, Equatable {
    /// "Claude and GPT models": a 5-hour and a weekly window.
    case thirdParty
    /// "Gemini Models": a weekly window (a 5-hour one on some plans).
    case gemini
}
