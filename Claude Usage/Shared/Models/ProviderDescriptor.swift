//
//  ProviderDescriptor.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

/// Declarative single source of truth for everything the app needs to know
/// about a provider: branding, status page, capabilities, and which settings
/// sections it exposes. UI and services gate on `capabilities`, never on
/// `provider == .codex`-style equality checks, so new providers require no
/// edits outside their own descriptor + implementation folder.
struct ProviderDescriptor {
    let id: Provider

    /// Brand name shown in pickers, badges, and notifications. Brand names
    /// are not localized.
    let displayName: String

    /// Asset catalog image for the provider mark; SF Symbol used as fallback.
    let logoAssetName: String
    let logoSystemSymbolFallback: String

    /// Statuspage-compatible status endpoint (same JSON schema across providers).
    let statusPageURL: URL?

    let capabilities: ProviderCapabilities

    /// Credential settings sections this provider exposes in the sidebar.
    let credentialSections: [SettingsSection]

    /// Localization keys for the two usage-window section labels.
    let primaryWindowLabelKey: String
    let secondaryWindowLabelKey: String
}

/// Capability flags that gate provider-specific features. Every gate in the
/// app reads one of these flags; a capability being `false` must cleanly
/// hide/no-op the feature (never throw).
struct ProviderCapabilities {
    /// Provider reports token counts, not just percentages. Gates
    /// `WeekDisplayMode.tokens` in the menu bar and token columns in CSV export.
    let tokenCounts: Bool

    /// Provider reports per-model weekly breakdowns (Opus/Sonnet/…). Gates
    /// per-model popover cards and model-specific notifications.
    let perModelBreakdown: Bool

    /// Provider has a billing/console API. Gates the `.apiConsole` settings
    /// section, the API usage card, the `.api` menu bar metric, and billing history.
    let consoleBilling: Bool

    /// Provider has a local CLI account this app syncs with on profile switch.
    /// Gates the `activateProfile` credential sync, statusline scripts, and the
    /// `.cliAccount`/`.claudeCode` settings sections.
    let cliAccountSync: Bool

    /// Provider supports auto-starting a usage window by sending a message.
    let autoStartSession: Bool

    /// Provider supports overage/extra-usage spend checks.
    let overageChecks: Bool

    /// Provider has published peak-hours windows worth highlighting.
    let peakHours: Bool

    /// Provider reports a prepaid credits balance.
    let credits: Bool
}
