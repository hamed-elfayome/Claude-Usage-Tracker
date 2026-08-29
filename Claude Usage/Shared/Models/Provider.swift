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

    var descriptor: ProviderDescriptor {
        ProviderRegistry.descriptor(for: self)
    }
}
