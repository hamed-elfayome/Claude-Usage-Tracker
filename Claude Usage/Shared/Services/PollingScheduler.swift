import Foundation

/// Computes the next poll interval based on rate-limit backoff and usage stability.
///
/// Does not own timers — the caller (MenuBarManager) owns the timer and queries
/// `currentInterval` after each refresh cycle.
struct PollingScheduler {

    // MARK: - Configuration

    private var baseInterval: TimeInterval
    private let maxBackoffInterval: TimeInterval
    private let stableThreshold: Int
    private let idleThreshold: Int
    private let stableMultiplier: Double
    private let idleMultiplier: Double
    private let similarityTolerance: Double

    // MARK: - State

    private var consecutiveRateLimitFailures: Int = 0
    private var stabilityStreak: Int = 0
    private var previousSessionPct: Double?
    private var previousWeeklyPct: Double?

    /// Computed interval incorporating both backoff and adaptive multipliers.
    var currentInterval: TimeInterval {
        if consecutiveRateLimitFailures > 0 {
            let backoff = baseInterval * pow(2.0, Double(consecutiveRateLimitFailures))
            return min(backoff, maxBackoffInterval)
        }

        let multiplier: Double
        if stabilityStreak >= idleThreshold {
            multiplier = idleMultiplier
        } else if stabilityStreak >= stableThreshold {
            multiplier = stableMultiplier
        } else {
            multiplier = 1.0
        }

        return baseInterval * multiplier
    }

    // MARK: - Initialization

    init(
        baseInterval: TimeInterval = Constants.RefreshIntervals.menuBar,
        maxBackoffInterval: TimeInterval = Constants.AdaptivePolling.maxBackoffInterval,
        stableThreshold: Int = Constants.AdaptivePolling.stableThreshold,
        idleThreshold: Int = Constants.AdaptivePolling.idleThreshold,
        stableMultiplier: Double = Constants.AdaptivePolling.stableMultiplier,
        idleMultiplier: Double = Constants.AdaptivePolling.idleMultiplier,
        similarityTolerance: Double = Constants.AdaptivePolling.similarityTolerance
    ) {
        self.baseInterval = baseInterval
        self.maxBackoffInterval = maxBackoffInterval
        self.stableThreshold = stableThreshold
        self.idleThreshold = idleThreshold
        self.stableMultiplier = stableMultiplier
        self.idleMultiplier = idleMultiplier
        self.similarityTolerance = similarityTolerance
    }

    // MARK: - Public Methods

    /// Record a successful API response. Resets backoff and updates stability streak.
    mutating func recordSuccess(usage: ClaudeUsage) {
        consecutiveRateLimitFailures = 0

        let sessionPct = usage.sessionPercentage
        let weeklyPct = usage.weeklyPercentage

        if let prevSession = previousSessionPct, let prevWeekly = previousWeeklyPct,
           abs(sessionPct - prevSession) <= similarityTolerance,
           abs(weeklyPct - prevWeekly) <= similarityTolerance {
            stabilityStreak += 1
        } else {
            // First call or data changed — reset streak but count this as the first observation
            stabilityStreak = previousSessionPct == nil ? 1 : 0
        }

        previousSessionPct = sessionPct
        previousWeeklyPct = weeklyPct
    }

    /// Record a 429 rate-limit error. Increments exponential backoff.
    mutating func recordRateLimitError() {
        consecutiveRateLimitFailures += 1
    }

    /// Record a non-rate-limit error. Does not affect polling interval.
    mutating func recordOtherError() {
        // Intentionally empty — per-request retry handles transient errors.
    }

    /// Update the base interval (e.g. when the user changes the setting or switches profiles).
    mutating func resetBaseInterval(_ interval: TimeInterval) {
        baseInterval = interval
    }
}
