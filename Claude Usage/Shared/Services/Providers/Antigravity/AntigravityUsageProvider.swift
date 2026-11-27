//
//  AntigravityUsageProvider.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  `agy` has ONE Google login, so every Antigravity profile is the same
//  account; profiles differ only in which quota pool they show. All of them
//  therefore share one cached, coalesced CLI result, and each maps its own
//  pool from it. (Unlike Codex, there is no "active profile only" rule: there
//  is no other account the shared login could belong to.)
//

import Foundation

@MainActor
final class AntigravityUsageProvider: UsageProviderService {
    static let shared = AntigravityUsageProvider()

    let provider: Provider = .antigravity

    private let locator: AntigravityCLILocator
    private let cache: AntigravityUsageCache

    init(
        fetcher: AntigravityUsageFetching? = nil,
        locator: AntigravityCLILocator = .shared,
        // Long enough to serve every Antigravity profile in one refresh cycle
        // from one agy call (~4 s), short enough that a manual Refresh at the
        // 30 s default interval never shows an old reading as new.
        maxAge: TimeInterval = 10
    ) {
        self.locator = locator
        self.cache = AntigravityUsageCache(fetcher: fetcher ?? AntigravityCLIClient(), maxAge: maxAge)
    }

    func hasCredentials(for profile: Profile) -> Bool {
        locator.cachedExecutable() != nil
    }

    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        try await fetchUsage(for: profile, forceRefresh: false)
    }

    /// `forceRefresh` bypasses the shared cache ("Test connection").
    func fetchUsage(for profile: Profile, forceRefresh: Bool) async throws -> ClaudeUsage {
        let response = try await cache.response(forceRefresh: forceRefresh)
        let pool = profile.antigravityPool ?? .thirdParty
        guard let usage = AntigravityUsageMapper.mapToUsage(response, pool: pool, previous: profile.claudeUsage) else {
            throw AppError(
                code: .apiParsingFailed,
                message: "error.antigravity_pool_missing".localized,
                technicalDetails: "agy /usage reported no bucket for pool '\(pool.rawValue)'",
                isRecoverable: true
            )
        }
        return usage
    }

    /// The raw response, for the settings view's per-bucket "Test connection".
    func fetchRawResponse(forceRefresh: Bool = true) async throws -> AntigravityUsageResponse {
        try await cache.response(forceRefresh: forceRefresh)
    }
}

/// One CLI call serves every profile: concurrent callers share the in-flight
/// task, and a successful result is reused for `maxAge` seconds. Failures are
/// not cached, so the next refresh retries. Explicitly main-actor isolated:
/// that serializes access without locks, which the coalescing relies on.
@MainActor
final class AntigravityUsageCache {
    private let fetcher: AntigravityUsageFetching
    private let maxAge: TimeInterval
    private let now: () -> Date

    private var cached: (at: Date, response: AntigravityUsageResponse)?
    private var inFlight: Task<AntigravityUsageResponse, Error>?

    init(fetcher: AntigravityUsageFetching, maxAge: TimeInterval, now: @escaping () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.maxAge = maxAge
        self.now = now
    }

    func response(forceRefresh: Bool = false) async throws -> AntigravityUsageResponse {
        if !forceRefresh, let cached, now().timeIntervalSince(cached.at) < maxAge {
            return cached.response
        }
        if let inFlight {
            return try await inFlight.value
        }
        let fetcher = self.fetcher
        let task = Task { try await fetcher.fetchUsage() }
        inFlight = task
        defer { inFlight = nil }
        let response = try await task.value
        cached = (now(), response)
        return response
    }
}

extension ProfileManager {
    /// Sets the active profile's Antigravity pool (from the setup wizard or
    /// the settings card) and refetches. The cached reading is dropped
    /// because it belongs to the previous pool or provider, and its reset
    /// times must not anchor the new pool's not-started windows.
    func setActiveAntigravityPool(_ pool: AntigravityPool) {
        guard var profile = activeProfile else { return }
        profile.antigravityPool = pool
        profile.claudeUsage = nil
        updateProfile(profile)
        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
    }
}
