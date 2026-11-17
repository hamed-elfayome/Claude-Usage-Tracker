import Foundation

// Saved-window projection (spec §5). Nothing here is stored or fed to rules.

struct PairView: Equatable {
    var sessionPercent: Double?      // nil without a 5-hour window
    var weeklyPercent: Double?
    var sessionProjected = false
    var weeklyProjected = false
    var sessionLeft: Double?
    var weeklyLeft: Double?
    var headroom: Double?
    var opusPercent: Double?
    var sonnetPercent: Double?
    var designPercent: Double?
    var fablePercent: Double?

    static func make(usage: ClaudeUsage?, sampledAt: Date?, now: Date) -> PairView {
        guard let u = usage else { return PairView() }
        func clamp(_ v: Double) -> Double { min(100, max(0, v)) }
        func expired(_ reset: Date?) -> Bool {
            guard let reset, reset <= now else { return false }
            return sampledAt.map { $0 < reset } ?? true
        }
        var v = PairView()
        if u.hasSessionLimit {
            v.sessionProjected = expired(u.sessionResetTime)
            let p = v.sessionProjected ? 0 : clamp(u.sessionPercentage)
            v.sessionPercent = p
            v.sessionLeft = clamp(100 - p)
        }
        v.weeklyProjected = expired(u.weeklyResetTime)
        let w = v.weeklyProjected ? 0 : clamp(u.weeklyPercentage)
        v.weeklyPercent = w
        v.weeklyLeft = clamp(100 - w)
        func model(_ pct: Double, _ reset: Date?) -> Double {
            (v.weeklyProjected || expired(reset)) ? 0 : clamp(pct)
        }
        v.opusPercent = model(u.opusWeeklyPercentage, nil)
        v.sonnetPercent = model(u.sonnetWeeklyPercentage, u.sonnetWeeklyResetTime)
        v.designPercent = model(u.designWeeklyPercentage, u.designWeeklyResetTime)
        v.fablePercent = model(u.fableWeeklyPercentage, u.fableWeeklyResetTime)
        v.headroom = [v.sessionLeft, v.weeklyLeft].compactMap { $0 }.min()
        return v
    }
}
