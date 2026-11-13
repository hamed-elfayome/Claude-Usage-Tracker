//
//  AutoStartSessionService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-11.
//

import Foundation
import Cocoa

/// Background service that monitors all profiles and auto-starts sessions when they reset
@MainActor
final class AutoStartSessionService {
    static let shared = AutoStartSessionService()

    // Timer for 5-minute check cycle
    private var checkTimer: Timer?

    // Track last check time to prevent duplicate checks on wake
    private var lastCheckTime: Date = .distantPast

    // Observers for sleep/wake notifications
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    let session: URLSession
    private let profiles: () -> [Profile]
    let saveUsage: (ClaudeUsage, UUID) -> Void
    private let notify: (Profile, Bool, String?) -> Void
    let logError: (String) -> Void

    // Track last captured reset time per profile to prevent duplicate auto-starts
    private var lastCapturedResetTime: [UUID: Date] = [:]

    // Spaces out retries after a failed start, so a start that keeps failing is not
    // attempted (and announced) on every 5-minute cycle (#334)
    private var retryBackoff = AutoStartRetryBackoff()

    private convenience init() {
        self.init(
            session: .shared,
            profiles: { ProfileManager.shared.profiles },
            saveUsage: { ProfileManager.shared.saveClaudeUsage($0, for: $1) },
            notify: { profile, success, error in
                NotificationManager.shared.sendAutoStartNotification(
                    profileName: profile.name,
                    success: success,
                    error: error,
                    settings: profile.notificationSettings
                )
            },
            logError: { LoggingService.shared.logError($0) }
        )
    }

    init(
        session: URLSession,
        profiles: @escaping () -> [Profile],
        saveUsage: @escaping (ClaudeUsage, UUID) -> Void,
        notify: @escaping (Profile, Bool, String?) -> Void,
        logError: @escaping (String) -> Void
    ) {
        self.session = session
        self.profiles = profiles
        self.saveUsage = saveUsage
        self.notify = notify
        self.logError = logError
    }

    // MARK: - Lifecycle

    func start() {
        // Start 5-minute check timer with tolerance for energy efficiency
        let timer = Timer.scheduledTimer(
            withTimeInterval: 300, // 5 minutes
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.performCheckIfNeeded(source: "timer")
            }
        }
        timer.tolerance = 30 // Allow up to 30 seconds of drift for energy efficiency
        checkTimer = timer

        // Register for wake/sleep notifications
        let workspace = NSWorkspace.shared

        wakeObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                LoggingService.shared.logInfo("Mac woke from sleep - checking for session resets")
                await self.performCheckIfNeeded(source: "wake")
            }
        }

        sleepObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            LoggingService.shared.logDebug("Mac going to sleep")
        }

        LoggingService.shared.logInfo("AutoStartSessionService started (5-minute cycle + wake detection)")

        // Perform immediate initial check to populate state
        Task { @MainActor in
            await self.performCheckIfNeeded(source: "startup")
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil

        // Remove observers
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let sleepObserver = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }

        LoggingService.shared.logInfo("AutoStartSessionService stopped")
    }

    // MARK: - Profile Checking

    /// Performs check with debouncing to prevent duplicate checks

    private func performCheckIfNeeded(source: String) async {
        // Debounce: Don't check if we checked less than 10 seconds ago
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTime)
        if timeSinceLastCheck < 10 {
            LoggingService.shared.logDebug("Skipping check from \(source) - checked \(Int(timeSinceLastCheck))s ago")
            return
        }

        lastCheckTime = Date()
        await checkAllProfiles(source: source)
    }

    func checkAllProfiles(source: String) async {
        LoggingService.shared.logDebug(
            "AutoStartSessionService: Checking all profiles for auto-start (source: \(source))"
        )

        // Get all profiles with auto-start enabled
        let profilesWithAutoStart = profiles().filter { $0.autoStartSessionEnabled }

        guard !profilesWithAutoStart.isEmpty else {
            LoggingService.shared.logDebug("No profiles with auto-start enabled")
            return
        }

        LoggingService.shared.logInfo("Checking \(profilesWithAutoStart.count) profile(s) with auto-start enabled")

        // Check each profile
        for profile in profilesWithAutoStart {
            await checkProfile(profile)
        }
    }

    private func checkProfile(_ profile: Profile) async {
        // Explicit capability gate: auto-start burns tokens via the claude.ai
        // conversation API — providers without it must be skipped by design,
        // not just incidentally via the credentials check below.
        guard profile.provider.descriptor.capabilities.autoStartSession else {
            LoggingService.shared.logDebug("Skipping profile '\(profile.name)' - provider does not support auto-start")
            return
        }

        // Skip if profile doesn't have Claude.ai credentials
        guard profile.hasClaudeAI else {
            LoggingService.shared.logDebug("Skipping profile '\(profile.name)' - no Claude.ai credentials")
            return
        }

        do {
            // Fetch current usage for this profile
            let (usage, hasOpenWindow) = try await fetchUsageForProfile(profile)

            // Plans without a 5-hour window (e.g. Ultra) have no session to start
            guard usage.hasSessionLimit else {
                LoggingService.shared.logDebug("Profile '\(profile.name)': skipping auto-start - plan has no session limit")
                return
            }

            let currentPercentage = usage.effectiveSessionPercentage

            // A session window that is open but unused reads 0% — often for
            // hours, because the initialization message (and light real usage)
            // rounds down to zero. Starting one then spends a request, and
            // leaves an empty conversation behind, to open something already
            // running. The in-memory `lastCapturedResetTime` guard below covers
            // the same run, but is lost across app restarts and never set for
            // windows the user opened themselves. Gating on the live reset time
            // from the API closes both gaps: only a window with no current
            // `resets_at` is genuinely waiting to be opened.
            if currentPercentage == 0.0 && !hasOpenWindow {
                // Check if we recently auto-started and should wait for reset
                if let lastResetTime = lastCapturedResetTime[profile.id],
                   Date() < lastResetTime {
                    let minutesRemaining = Int(lastResetTime.timeIntervalSinceNow / 60)
                    LoggingService.shared.logDebug(
                        "Profile '\(profile.name)': skipping auto-start - \(minutesRemaining)m until session reset"
                    )
                    return
                }

                // An unused five-hour window does not restore the weekly allowance.
                // Check the account's explicit spending permission, not cached costs
                // or the tracker's optional extra-usage display setting.
                if usage.weeklyPercentage >= 100 {
                    guard try await fetchExtraUsageEnabled(for: profile) else {
                        LoggingService.shared.logInfo(
                            "Profile '\(profile.name)': skipping auto-start - "
                                + "weekly allowance exhausted and extra usage disabled"
                        )
                        return
                    }
                }

                if let wait = retryBackoff.waitRemaining(for: profile.id, now: Date()) {
                    LoggingService.shared.logDebug(
                        "Profile '\(profile.name)': skipping auto-start - retrying in \(Int(wait / 60))m after a failed start"
                    )
                    return
                }

                LoggingService.shared.logInfo("Session at 0% for profile '\(profile.name)' - triggering auto-start")

                // Auto-start the session
                await autoStartSession(for: profile)
            } else {
                // Session is active, clear any tracked reset time since usage endpoint is now showing correct data
                lastCapturedResetTime.removeValue(forKey: profile.id)
                let windowState = hasOpenWindow ? "open" : "closed"
                LoggingService.shared.logDebug(
                    "Profile '\(profile.name)': session at \(currentPercentage)% (window \(windowState))"
                )
            }

        } catch {
            // Network, parsing, and permission errors must all stop this check.
            logError("Failed to check profile '\(profile.name)': \(error.localizedDescription)")
        }
    }

    private func autoStartSession(for profile: Profile) async {
        do {
            // Call the initialization API for this profile and get response data
            let responseData = try await sendInitializationMessage(for: profile)

            // Capture reset time from response to prevent duplicate auto-starts
            if let resetTime = parseCompletionResponseForResetTime(responseData) {
                lastCapturedResetTime[profile.id] = resetTime
                LoggingService.shared.logInfo("Captured session reset time for '\(profile.name)': \(resetTime)")
            }

            retryBackoff.recordSuccess(for: profile.id)
            LoggingService.shared.logInfo("Successfully auto-started session for profile '\(profile.name)'")

            // Send success notification
            notify(profile, true, nil)

        } catch {
            // Initialization can fail during transport or response validation.
            logError("Failed to auto-start session for profile '\(profile.name)': \(error.localizedDescription)")

            // Announce the first failure of a streak only; the retries that follow are
            // spaced out and would otherwise repeat the same notification.
            let isFirstFailure = retryBackoff.recordFailure(for: profile.id, now: Date())
            if isFirstFailure {
                notify(profile, false, error.localizedDescription)
            }
        }
    }
}

/// Retry spacing for auto-start attempts that fail (#334).
///
/// Each consecutive failure doubles the wait before the next attempt, from 15
/// minutes up to 2 hours. A successful start clears the streak.
struct AutoStartRetryBackoff {
    static let baseDelay: TimeInterval = 15 * 60
    static let maxDelay: TimeInterval = 2 * 60 * 60

    private var failures: [UUID: Int] = [:]
    private var nextAttempt: [UUID: Date] = [:]

    /// Time left before `profileId` may be tried again, or nil if it may be tried now.
    func waitRemaining(for profileId: UUID, now: Date) -> TimeInterval? {
        guard let next = nextAttempt[profileId], next > now else { return nil }
        return next.timeIntervalSince(now)
    }

    /// Records a failed start. Returns true when it is the first failure of a streak.
    @discardableResult
    mutating func recordFailure(for profileId: UUID, now: Date) -> Bool {
        let count = (failures[profileId] ?? 0) + 1
        failures[profileId] = count
        let delay = min(Self.baseDelay * pow(2, Double(count - 1)), Self.maxDelay)
        nextAttempt[profileId] = now.addingTimeInterval(delay)
        return count == 1
    }

    mutating func recordSuccess(for profileId: UUID) {
        failures.removeValue(forKey: profileId)
        nextAttempt.removeValue(forKey: profileId)
    }
}
