//
//  CodexUsageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//

import Foundation

final class CodexUsageProvider: UsageProviderService {
    static let shared = CodexUsageProvider()

    let provider: Provider = .codex

    private let authService = CodexAuthService.shared
    private let apiService = CodexAPIService.shared

    private init() {}

    func hasCredentials(for profile: Profile) -> Bool {
        profile.hasUsageCredentials
    }

    /// load credentials → refresh if stale (>8 days) → fetch → map.
    /// On a 401/403 (access token expired before the 8-day mark), force one
    /// refresh and retry once — the Codex CLI has no equivalent of Anthropic's
    /// system-keychain fallback, so a failed retry surfaces the error.
    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        // The shared ~/.codex/auth.json reflects ONE signed-in Codex account.
        // A profile without its own pasted credentials may fall back to it
        // only when the file cannot belong to another profile (see
        // `mayUseSharedAuthFile`). Otherwise it would silently display (and
        // record into its history) another account's stats. Mirrors the
        // Anthropic provider's system-keychain rule.
        if profile.codexCredentialsJSON == nil {
            let (activeProfileId, allProfiles) = await MainActor.run {
                (ProfileManager.shared.activeProfile?.id, ProfileManager.shared.profiles)
            }
            guard Self.mayUseSharedAuthFile(profile, activeProfileId: activeProfileId, profiles: allProfiles) else {
                throw AppError(
                    code: .providerCredentialsNotFound,
                    message: "error.codex_credentials_not_found".localized,
                    technicalDetails: "Non-active profile '\(profile.name)' has no pasted Codex credentials, and auth.json could belong to another Codex profile",
                    isRecoverable: true,
                    recoverySuggestion: "error.codex_credentials_not_found.suggestion".localized
                )
            }
        }

        var credentials = try authService.loadCredentials(for: profile)
        credentials = try await authService.refreshIfNeeded(credentials, for: profile)

        let previousUsage = profile.claudeUsage
        do {
            let response = try await apiService.fetchUsage(credentials: credentials)
            return CodexAPIService.mapToUsage(response, previous: previousUsage)
        } catch let error as AppError where error.code == .providerAuthExpired {
            guard !credentials.refreshToken.isEmpty else { throw error }
            let refreshed = try await authService.refreshIfNeeded(credentials, for: profile, force: true)
            let response = try await apiService.fetchUsage(credentials: refreshed)
            return CodexAPIService.mapToUsage(response, previous: previousUsage)
        }
    }

    /// Whether `profile`, which has no pasted Codex credentials, may read the
    /// shared `~/.codex/auth.json`.
    ///
    /// The active profile always may. A non-active profile may only when it is
    /// the single Codex profile without credentials of its own: the file then
    /// has no other profile it could belong to, so a Codex profile shown next
    /// to an active Claude profile keeps refreshing (#335). With two or more
    /// such profiles the file is ambiguous and stays reserved for the active one.
    static func mayUseSharedAuthFile(_ profile: Profile, activeProfileId: UUID?, profiles: [Profile]) -> Bool {
        if profile.id == activeProfileId { return true }
        let sharingProfiles = profiles.filter { $0.provider == .codex && $0.codexCredentialsJSON == nil }
        return sharingProfiles.count == 1 && sharingProfiles.first?.id == profile.id
    }
}
