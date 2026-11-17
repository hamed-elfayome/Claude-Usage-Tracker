import Foundation

// Rows of the Teams list (spec §11). Pure.

struct TeamRow: Identifiable, Equatable {
    enum State: Equatable { case ok, needsLogin, notSignedIn, old, unreachable }
    let id: String
    let pair: PairRef
    let profileName: String
    let orgName: String
    let isCurrent: Bool
    let view: PairView
    let lastSampleAt: Date?
    let state: State
    let deleteAfterDays: Int?

    private static let day: TimeInterval = 86_400
    static let deleteAfter: TimeInterval = 15 * day

    static func build(profiles: [Profile], global: TeamTrackingGlobalState,
                      hasCredential: (Profile) -> Bool, now: Date) -> [TeamRow] {
        var rows: [TeamRow] = []
        for profile in profiles where profile.provider == .anthropic {
            guard let tracking = profile.orgTracking else { continue }
            var accountState: State = .ok
            if case .needsLogin = tracking.authState { accountState = .needsLogin }
            else if !hasCredential(profile) { accountState = .notSignedIn }
            for org in tracking.orgs {
                let pair = PairRef(profileId: profile.id, orgId: org.orgId)
                var state = accountState
                var days: Int?
                switch org.status {
                case .member: break
                case .unreachable: state = .unreachable
                case .old:
                    state = .old
                    let seen = org.lastSeenInListAt ?? org.firstSeenAt
                    let left = seen.addingTimeInterval(deleteAfter).timeIntervalSince(now) / day
                    days = max(0, Int(left.rounded(.up)))
                }
                rows.append(TeamRow(
                    id: "\(profile.id)_\(org.orgId)", pair: pair, profileName: profile.name, orgName: org.name,
                    isCurrent: global.current == pair,
                    view: PairView.make(usage: org.lastUsage, sampledAt: org.lastSampleAt, now: now),
                    lastSampleAt: org.lastSampleAt, state: state, deleteAfterDays: days))
            }
        }
        func name(_ r: TeamRow) -> String { "\(r.profileName) · \(r.orgName)" }
        func group(_ r: TeamRow) -> Int {
            if r.isCurrent { return 0 }
            switch r.state {
            case .ok: return 1
            case .needsLogin, .notSignedIn: return 2
            case .old, .unreachable: return 3
            }
        }
        return rows.sorted { a, b in
            let ga = group(a), gb = group(b)
            if ga != gb { return ga < gb }
            if ga == 1 {
                // nil headroom last
                let ha = a.view.headroom ?? -1, hb = b.view.headroom ?? -1
                if ha != hb { return ha > hb }
                let wa = a.view.weeklyLeft ?? -1, wb = b.view.weeklyLeft ?? -1
                if wa != wb { return wa > wb }
            }
            return name(a) < name(b)
        }
    }

    static func recentEvents(_ global: TeamTrackingGlobalState, limit: Int = 5) -> [TeamEvent] {
        Array(global.events.sorted { $0.date > $1.date }.prefix(limit))
    }
}
