//
//  AnthropicUsageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  Wraps the pre-existing Anthropic fetch chain behind UsageProviderService.
//  The bodies below were MOVED VERBATIM from MenuBarManager (multi-profile
//  path) and its single-profile refresh path — behavior must stay identical.
//

import Foundation

final class AnthropicUsageProvider: UsageProviderService {
    static let shared = AnthropicUsageProvider()

    let provider: Provider = .anthropic

    // Concrete type: the per-profile fetch overloads (sessionKey/oauthAccessToken)
    // are not part of APIServiceProtocol.
    private let apiService: ClaudeAPIService

    init(apiService: ClaudeAPIService = ClaudeAPIService()) {
        self.apiService = apiService
    }

    /// Profile credentials plus the system-keychain CLI fallback that
    /// `ClaudeAPIService.getAuthentication()` can discover during the actual
    /// API call (mirrors the old `MenuBarManager.hasAnyAvailableCredentials`).
    func hasCredentials(for profile: Profile) -> Bool {
        profile.hasUsageCredentials
            || ClaudeCodeSyncService.shared.hasUsableSystemCredentials()
    }

    /// Fetches usage data for a specific profile using its credentials.
    /// (Moved verbatim from `MenuBarManager.fetchUsageForProfile(_:)`.)
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        // Priority 1: claude.ai session key (cookie-based)
        if let sessionKey = profile.claudeSessionKey,
           let orgId = profile.organizationId {
            return try await apiService.fetchUsageData(sessionKey: sessionKey, organizationId: orgId)
        }

        // Priority 2: CLI OAuth credentials.
        // `ensureFreshCredentials` picks the source automatically:
        //   - If `profile.customKeychainServiceName` is set → pull fresh from that keychain entry
        //     (which Claude Code rotates during normal CLI use). No network refresh needed when
        //     the token there is still valid; otherwise transparently refresh via the
        //     refresh_token grant and write back to both keychain and profile cache.
        //   - Otherwise → use the profile's cached `cliCredentialsJSON`, refreshing if expired.
        // If `ensureFreshCredentials` returns nil (e.g. network failure during refresh), fall
        // back to the stored cliCredentialsJSON so a still-valid cached token isn't wasted.
        if profile.cliCredentialsJSON != nil || profile.customKeychainServiceName != nil {
            let usableJSON = await ClaudeCodeSyncService.shared.ensureFreshCredentials(for: profile.id)
                ?? profile.cliCredentialsJSON
            if let usableJSON = usableJSON,
               !ClaudeCodeSyncService.shared.isTokenExpired(usableJSON),
               let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: usableJSON) {
                return try await apiService.fetchUsageData(oauthAccessToken: accessToken)
            }
        }

        // Priority 3: System Keychain CLI OAuth token
        // Only use system keychain for the active profile — the keychain/credentials file
        // reflects the currently active `claude` CLI session. Using it for a non-active
        // profile would silently return the active profile's stats.
        if profile.id == ProfileManager.shared.activeProfile?.id,
           let systemCredentials = try? ClaudeCodeSyncService.shared.readSystemCredentials(),
           !ClaudeCodeSyncService.shared.isTokenExpired(systemCredentials),
           let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: systemCredentials) {
            return try await apiService.fetchUsageData(oauthAccessToken: accessToken)
        }

        // No usable live credential (e.g. a non-active profile whose CLI token expired and
        // must not be refreshed independently — that would rotate a token another tool such as
        // `cux` owns). Rather than surfacing a blocking "session key not found" dialog on every
        // profile switch, fall back to the profile's last-known usage snapshot. Per-model weekly
        // quotas change slowly, so a slightly stale reading is far better UX than an error
        // popup — and the active profile still refreshes live every cycle. (#290)
        if let cached = profile.claudeUsage {
            LoggingService.shared.log("AnthropicUsageProvider: no live credential for '\(profile.name)'; showing last-known cached usage")
            return cached
        }

        throw AppError(
            code: .sessionKeyNotFound,
            message: "Missing credentials for profile '\(profile.name)'",
            isRecoverable: false
        )
    }

    /// The single-profile refresh path historically used the no-arg
    /// `fetchUsageData()`, whose internal `getAuthentication()` chain covers
    /// the active profile plus system-level fallbacks. Keep that exact path.
    func fetchUsageForActiveProfile(_ profile: Profile) async throws -> ClaudeUsage {
        try await apiService.fetchUsageData()
    }
}
