import Foundation

// Pure current-pair detection (docs/specs/multi-team-tracking.md §4). No network, `now` injected.

struct RoundCandidate {
    let pair: PairRef
    let previous: RoundReading?
    let latest: ClaudeUsage?
    let latestAt: Date?
}

struct RoundInput {
    let now: Date
    let current: PairRef?
    let manualPickAt: Date?
    let lastRoundAt: Date?
    let candidates: [RoundCandidate]   // (profile order, org order)
}

struct RoundOutput: Equatable {
    let current: PairRef?
    let switched: Bool
    let readings: [PairRef: RoundReading]
    let rises: [PairRef: Double]
    let clearManualPick: Bool
}

enum CurrentPairDetector {
    static let minRise = 1.0
    static let tieEpsilon = 0.05
    static let staleAfter: TimeInterval = 450

    static func metric(_ u: ClaudeUsage) -> (percent: Double, reset: Date) {
        u.hasSessionLimit ? (u.sessionPercentage, u.sessionResetTime) : (u.weeklyPercentage, u.weeklyResetTime)
    }

    /// nil = re-baseline only (no previous reading, or it is stale).
    static func rise(previous: RoundReading?, latest: RoundReading) -> Double? {
        guard let p = previous, latest.at.timeIntervalSince(p.at) <= staleAfter else { return nil }
        let raw = ResetDetection.isReset(from: p.resetTime, to: latest.resetTime)
            ? latest.percent
            : latest.percent - p.percent
        return raw < minRise ? 0 : raw
    }

    static func evaluate(_ input: RoundInput) -> RoundOutput {
        var readings: [PairRef: RoundReading] = [:]
        var rises: [PairRef: Double] = [:]
        var order: [PairRef] = []
        for c in input.candidates {
            guard let usage = c.latest else { continue }
            let m = metric(usage)
            let reading = RoundReading(percent: m.percent, resetTime: m.reset, at: c.latestAt ?? input.now)
            readings[c.pair] = reading
            if let r = rise(previous: c.previous, latest: reading) {
                rises[c.pair] = r
                order.append(c.pair)
            }
        }

        if let pick = input.manualPickAt, input.lastRoundAt.map({ pick > $0 }) ?? true {
            return RoundOutput(current: input.current, switched: false, readings: readings, rises: [:], clearManualPick: true)
        }

        var next = input.current
        if let top = rises.values.max(), top >= minRise {
            let tied = order.filter { rises[$0]! >= top - tieEpsilon }
            if let cur = input.current, tied.contains(cur) {
                next = cur
            } else if tied.count == 1 || input.current == nil {
                next = tied.first
            }
        }
        return RoundOutput(current: next, switched: next != input.current, readings: readings, rises: rises, clearManualPick: false)
    }
}
