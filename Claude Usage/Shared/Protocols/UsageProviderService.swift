//
//  UsageProviderService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// The fetch contract every usage provider implements. Resolved through
/// `ProviderRegistry.service(for:)` — call sites never reference a concrete
/// provider type, so new providers plug in without core-file changes.
protocol UsageProviderService {
    var provider: Provider { get }

    /// Whether the profile can fetch usage right now, including any
    /// provider-specific system-level credential fallbacks that only apply
    /// to the active profile.
    func hasCredentials(for profile: Profile) -> Bool

    /// Fetches usage for a specific (possibly non-active) profile using only
    /// that profile's own credentials.
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage

    /// Fetches usage for the ACTIVE profile. Providers may use a broader
    /// auth chain here (e.g. Anthropic's system-keychain CLI fallback, which
    /// reflects the currently signed-in CLI account and is therefore only
    /// safe for the active profile). Defaults to `fetchUsage(for:)`.
    func fetchUsageForActiveProfile(_ profile: Profile) async throws -> ClaudeUsage
}

extension UsageProviderService {
    func fetchUsageForActiveProfile(_ profile: Profile) async throws -> ClaudeUsage {
        try await fetchUsage(for: profile)
    }
}
