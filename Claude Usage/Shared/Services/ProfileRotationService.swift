//
//  ProfileRotationService.swift
//  Claude Usage
//

import Foundation

/// Evaluates whether the active profile should be rotated to another profile
/// based on session capacity using a drain-and-switch strategy.
@MainActor
class ProfileRotationService {
    static let shared = ProfileRotationService()

    private let profileManager = ProfileManager.shared

    /// Timestamp of the last rotation to prevent rapid switching
    private var lastRotationTime: Date = .distantPast

    private init() {}

    // MARK: - Public API

    /// Evaluates rotation after a usage refresh. Returns the profile ID to rotate to, or nil.
    func evaluateRotation() -> UUID? {
        guard let active = profileManager.activeProfile else { return nil }

        // Need at least 2 rotation-eligible profiles (opted in + have session credentials)
        let candidates = profileManager.profiles.filter { $0.autoRotateEnabled && $0.hasSessionCredentials }
        guard candidates.count >= 2 else {
            LoggingService.shared.log("AutoRotation: Only \(candidates.count) eligible candidate(s), need 2+")
            return nil
        }

        guard active.autoRotateEnabled else {
            LoggingService.shared.log("AutoRotation: Active profile '\(active.name)' has autoRotate disabled")
            return nil
        }

        // Check if active profile needs rotation: session above threshold OR weekly limit hit
        guard let activeUsage = active.claudeUsage else {
            LoggingService.shared.log("AutoRotation: Active profile '\(active.name)' has no usage data")
            return nil
        }
        let sessionExhausted = activeUsage.sessionPercentage >= Constants.AutoRotation.sessionThreshold
        let weeklyExhausted = activeUsage.weeklyPercentage >= 99.0
        LoggingService.shared.log("AutoRotation: '\(active.name)' session=\(activeUsage.sessionPercentage)% weekly=\(activeUsage.weeklyPercentage)% sessionExhausted=\(sessionExhausted) weeklyExhausted=\(weeklyExhausted)")
        guard sessionExhausted || weeklyExhausted else { return nil }

        // Cooldown: don't rotate too frequently
        let elapsed = Date().timeIntervalSince(lastRotationTime)
        guard elapsed > Constants.AutoRotation.cooldownInterval else {
            LoggingService.shared.log("AutoRotation: Cooldown active (\(Int(elapsed))s elapsed)")
            return nil
        }

        let activeCapacity = effectiveCapacity(for: active)

        // Log candidates without usage data, then find the one with highest effective capacity
        let otherCandidates = candidates.filter { $0.id != active.id }
        for candidate in otherCandidates {
            if let usage = candidate.claudeUsage {
                let cap = effectiveCapacity(for: candidate)
                LoggingService.shared.log("AutoRotation: Candidate '\(candidate.name)' session=\(usage.sessionPercentage)% weekly=\(usage.weeklyPercentage)% capacity=\(cap)")
            } else {
                LoggingService.shared.log("AutoRotation: Skipping '\(candidate.name)' (no usage data)")
            }
        }

        let bestCandidate = otherCandidates
            .filter { $0.claudeUsage != nil }
            .max { effectiveCapacity(for: $0) < effectiveCapacity(for: $1) }

        guard let target = bestCandidate else {
            LoggingService.shared.log("AutoRotation: No suitable candidate found")
            return nil
        }

        let bestCapacity = effectiveCapacity(for: target)

        // Hysteresis: only rotate if the candidate has meaningfully more capacity.
        // When activeCapacity is 0, any positive bestCapacity wins (ratio is infinite).
        let meetsThreshold = activeCapacity > 0
            ? bestCapacity / activeCapacity >= Constants.AutoRotation.hysteresisMultiplier
            : bestCapacity > 0

        LoggingService.shared.log("AutoRotation: activeCapacity=\(activeCapacity) bestCapacity=\(bestCapacity) target='\(target.name)' meetsThreshold=\(meetsThreshold)")

        return meetsThreshold ? target.id : nil
    }

    /// Records that a rotation was performed (for cooldown tracking)
    func recordRotation() {
        lastRotationTime = Date()
    }

    // MARK: - Capacity Calculation

    /// Calculates effective remaining capacity: remaining_session% x tier_weight x weekly_factor
    /// Weekly usage >= 99% treats the profile as fully exhausted (capacity 0).
    func effectiveCapacity(for profile: Profile) -> Double {
        guard let usage = profile.claudeUsage else { return 0 }

        // Weekly limit nearly hit means the account is effectively capped
        let weeklyPct = min(max(0, usage.weeklyPercentage), 100.0)
        if weeklyPct >= 99.0 { return 0 }

        let remainingSession = max(0, 100.0 - usage.sessionPercentage)
        let tierWeight = (profile.accountTier ?? .pro).weight
        let baseCapacity = remainingSession * tierWeight

        // Scale down linearly as weekly usage climbs
        let weeklyFactor = 1.0 - (weeklyPct / 100.0)
        return max(0, baseCapacity * weeklyFactor)
    }
}
