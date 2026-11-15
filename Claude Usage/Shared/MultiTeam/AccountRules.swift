import Foundation

// Per-account event state machine (docs/specs/multi-team-tracking.md §6). Pure: no network, Keychain or Date().

struct OrgListEntry: Equatable {
    var orgId: String
    var name: String
    var seat: SeatFingerprint? = nil
    var canChat: Bool = true
}

struct AccountObservation {
    var now: Date
    var hasSessionKey: Bool = true
    var credentialFingerprint: String? = nil
    var credentialOrgId: String? = nil
    var credentialSeat: SeatFingerprint? = nil
    var orgList: [OrgListEntry]? = nil          // nil = none this time or failed
    var orgListAuthFailed: Bool = false
    var peerConfirmedRemovals: Set<String> = []
    var samples: [String: ClaudeUsage] = [:]
    var usageMembershipFailures: Set<String> = []
    var oauthUnauthorized: Bool = false
    var refreshRejected: Bool = false
}

struct ResetSnapshot: Equatable {
    let orgId: String
    let window: UsageWindow
    let previous: ClaudeUsage
}

struct ConfirmedRemoval: Equatable {
    let orgId: String
    let movedTo: String?
}

struct AccountResult {
    var state: OrgTrackingState
    var events: [TeamEvent] = []
    var resetSnapshots: [ResetSnapshot] = []
    var confirmedRemovals: [ConfirmedRemoval] = []
    var followedOrgId: String? = nil            // non-nil only when it must change
    var deletedHistoryKeys: [String] = []
    var acceptedSamples: [String: ClaudeUsage] = [:]
}

enum AccountRules {
    private static let day: TimeInterval = 86_400
    private static let listDebounce: TimeInterval = 60
    private static let failureWindow: TimeInterval = 10 * 60
    private static let pendingMaxAge: TimeInterval = 30 * 60

    private struct Run {
        let obs: AccountObservation
        let profileId: UUID
        let profileName: String
        var state: OrgTrackingState
        var result: AccountResult
        var followed: String?
        var followedChanged = false
        var identity: Set<String> = []          // pairs with an identity event this run
        var resolved: Set<String> = []          // pairs whose pending change was handled or created this run
        var listNames: [String: String] = [:]
        var blocked = false                     // needsLogin: no membership/sample rules
        var now: Date { obs.now }

        mutating func setFollowed(_ id: String) {
            followed = id
            followedChanged = true
        }

        mutating func emit(_ kind: TeamEvent.Kind) {
            var names = [String: String]()
            for o in state.orgs { names[o.orgId] = o.name }
            for (k, v) in listNames { names[k] = v }
            names[profileId.uuidString] = profileName
            result.events.append(TeamEvent(kind: kind, names: names, date: now))
        }

        mutating func markIdentity(_ orgId: String) {
            identity.insert(orgId)
            let at = obs.now
            state.updateOrg(orgId) {
                $0.baselineStartedAt = at
                $0.pending = nil
            }
        }

        mutating func newHistoryKey(_ orgId: String) -> String {
            if !state.legacyHistoryKeyAssigned {
                state.legacyHistoryKeyAssigned = true
                return profileId.uuidString
            }
            return TeamTrackingMigration.pairHistoryKey(profileId: profileId, orgId: orgId)
        }

        mutating func addMember(_ orgId: String, name: String, seat: SeatFingerprint?, inList: Bool) {
            let key = newHistoryKey(orgId)
            state.orgs.append(TrackedOrg(
                orgId: orgId, name: name, status: .member, historyKey: key, seat: seat,
                lastUsage: nil, lastSampleAt: nil, firstSeenAt: now,
                lastSeenInListAt: inList ? now : nil, missingFromListCount: 0,
                lastMembershipFailureAt: nil, pending: nil, baselineStartedAt: now, roundReading: nil))
            identity.insert(orgId)
        }
    }

    static func apply(_ obs: AccountObservation, to state: OrgTrackingState, profileId: UUID,
                      profileName: String, followedOrgId: String?) -> AccountResult {
        var run = Run(obs: obs, profileId: profileId, profileName: profileName, state: state,
                      result: AccountResult(state: state), followed: followedOrgId)
        let storedFingerprint = state.credentialFingerprint
        if let list = obs.orgList { for e in list { run.listNames[e.orgId] = e.name } }

        ruleU(&run)
        ruleL(&run, storedFingerprint: storedFingerprint)
        if let fp = obs.credentialFingerprint { run.state.credentialFingerprint = fp }
        if !run.blocked {
            ruleM(&run)
            ruleT(&run)
            ruleS(&run)
            ruleR(&run)
            recordSamples(&run)
        }
        if let id = obs.credentialOrgId, !id.isEmpty { run.state.credentialOrgId = id }
        ruleX(&run)

        run.result.state = run.state
        run.result.followedOrgId = run.followedChanged ? run.followed : nil
        return run.result
    }

    // MARK: U - unknown org

    private static func ruleU(_ run: inout Run) {
        let unknown = TrackedOrg.unknownOrgId
        guard run.state.org(unknown) != nil else { return }
        var target: (id: String, name: String?)?
        if let c = run.obs.credentialOrgId, !c.isEmpty {
            target = (c, run.listNames[c])
        } else if let list = run.obs.orgList?.filter({ $0.canChat }), !list.isEmpty {
            if list.count == 1 {
                target = (list[0].orgId, list[0].name)
            } else if let f = run.followed, let e = list.first(where: { $0.orgId == f }) {
                target = (e.orgId, e.name)
            }
        }
        guard let t = target else { return }
        if run.state.org(t.id) != nil {
            run.state.orgs.removeAll { $0.orgId == unknown }
        } else {
            run.state.updateOrg(unknown) {
                $0.orgId = t.id
                if let n = t.name { $0.name = n }
            }
        }
        if run.followed == unknown { run.setFollowed(t.id) }
    }

    // MARK: L - login loss

    private static func ruleL(_ run: inout Run, storedFingerprint: String?) {
        let obs = run.obs
        var wasLoggedOut = false
        if case .needsLogin = run.state.authState { wasLoggedOut = true }

        let fingerprintChanged = obs.credentialFingerprint != nil && obs.credentialFingerprint != storedFingerprint
        if obs.oauthUnauthorized {
            run.state.consecutiveOAuthUnauthorized += 1
        } else if fingerprintChanged || !obs.samples.isEmpty {
            run.state.consecutiveOAuthUnauthorized = 0
        }
        var failure: String?
        if obs.refreshRejected {
            failure = "Claude Code login was revoked"
        } else if obs.orgListAuthFailed {
            failure = "claude.ai session expired"
        } else if obs.oauthUnauthorized && !obs.hasSessionKey && run.state.consecutiveOAuthUnauthorized >= 2 {
            failure = "Log in again"
        }

        if let reason = failure {
            run.blocked = true
            if !wasLoggedOut {
                run.state.authState = .needsLogin(reason: reason, since: obs.now)
                run.emit(.loginLost(profileId: run.profileId, reason: reason))
            }
        } else if wasLoggedOut {
            let listSucceeded = !(obs.orgList ?? []).isEmpty
            if fingerprintChanged || listSucceeded || !obs.samples.isEmpty {
                run.state.authState = .ok
                run.state.consecutiveOAuthUnauthorized = 0
                run.emit(.loginRestored(profileId: run.profileId))
            } else {
                run.blocked = true
            }
        }
    }

    // MARK: M - membership

    private static func ruleM(_ run: inout Run) {
        let now = run.now
        for id in run.obs.usageMembershipFailures {
            run.state.updateOrg(id) { if $0.status == .member { $0.lastMembershipFailureAt = now } }
        }
        guard run.obs.hasSessionKey, let raw = run.obs.orgList, !raw.isEmpty else { return }
        defer { run.state.lastOrgListAt = now }
        let list = raw.filter { $0.canChat }
        guard !list.isEmpty else { return }
        let listedIds = Set(list.map { $0.orgId })
        let canCount = run.state.lastOrgListAt.map { now.timeIntervalSince($0) >= listDebounce } ?? true

        for e in list {
            if let org = run.state.org(e.orgId) {
                switch org.status {
                case .member:
                    run.state.updateOrg(e.orgId) {
                        $0.missingFromListCount = 0
                        $0.lastSeenInListAt = now
                        $0.name = e.name
                    }
                case .old:
                    run.state.updateOrg(e.orgId) {
                        $0.status = .member
                        $0.missingFromListCount = 0
                        $0.lastSeenInListAt = now
                        $0.name = e.name
                    }
                    run.markIdentity(e.orgId)
                    run.emit(.teamRejoined(profileId: run.profileId, org: e.orgId))
                case .unreachable:
                    break
                }
            } else {
                run.addMember(e.orgId, name: e.name, seat: e.seat, inList: true)
                run.emit(.teamAdded(profileId: run.profileId, org: e.orgId))
            }
        }

        // Missing members: count, then decide who is confirmed gone.
        var gone: [TrackedOrg] = []
        for org in run.state.orgs where org.status == .member && org.orgId != TrackedOrg.unknownOrgId && !listedIds.contains(org.orgId) {
            var count = org.missingFromListCount
            if canCount { count += 1 }
            run.state.updateOrg(org.orgId) { $0.missingFromListCount = count }
            let failedRecently = org.lastMembershipFailureAt.map {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age <= failureWindow
            } ?? false
            if count >= 2 || failedRecently || run.obs.peerConfirmedRemovals.contains(org.orgId) {
                gone.append(org)
            }
        }
        let goneIds = Set(gone.map { $0.orgId })
        for a in gone {
            let anchor = (a.lastSeenInListAt ?? a.firstSeenAt).addingTimeInterval(-day)
            let target = run.state.orgs
                .filter { $0.status == .member && listedIds.contains($0.orgId)
                    && !goneIds.contains($0.orgId) && $0.firstSeenAt >= anchor }
                .max { $0.firstSeenAt < $1.firstSeenAt }
            run.state.updateOrg(a.orgId) {
                $0.status = .old
                $0.pending = nil
            }
            run.identity.insert(a.orgId)
            if let b = target {
                run.markIdentity(b.orgId)
                run.emit(.adminMove(profileId: run.profileId, from: a.orgId, to: b.orgId))
            } else {
                run.emit(.teamRemoved(profileId: run.profileId, org: a.orgId))
            }
            run.result.confirmedRemovals.append(ConfirmedRemoval(orgId: a.orgId, movedTo: target?.orgId))
            if run.followed == a.orgId {
                if let b = target?.orgId ?? run.state.orgs.first(where: { $0.status == .member && $0.orgId != a.orgId && $0.orgId != TrackedOrg.unknownOrgId && !goneIds.contains($0.orgId) })?.orgId {
                    run.setFollowed(b)
                }
            }
        }
    }

    // MARK: T - OAuth-only team change

    private static func ruleT(_ run: inout Run) {
        guard !run.obs.hasSessionKey, let c1 = run.obs.credentialOrgId, !c1.isEmpty,
              let c0 = run.state.credentialOrgId, !c0.isEmpty, c0 != c1 else { return }
        if run.state.org(c1) == nil {
            run.addMember(c1, name: "Team", seat: nil, inList: false)
        } else {
            run.state.updateOrg(c1) { $0.status = .member; $0.missingFromListCount = 0 }
        }
        run.state.updateOrg(c0) { $0.status = .unreachable }
        run.markIdentity(c1)
        run.markIdentity(c0)
        run.emit(.teamChanged(profileId: run.profileId, from: c0, to: c1))
        run.setFollowed(c1)
    }

    // MARK: S - seat change

    private static func incomingSeat(_ run: Run, _ orgId: String) -> SeatFingerprint? {
        if let s = run.obs.orgList?.first(where: { $0.orgId == orgId })?.seat { return s }
        if orgId == run.obs.credentialOrgId { return run.obs.credentialSeat }
        return nil
    }

    private static func ruleS(_ run: inout Run) {
        let accepted = acceptedOrgIds(run)
        // Sweep: a pending older than pendingMaxAge can never confirm; clear it so it cannot wedge later candidates.
        for org in run.state.orgs {
            if let p = org.pending, run.now.timeIntervalSince(p.detectedAt) > pendingMaxAge {
                run.state.updateOrg(org.orgId) { $0.pending = nil }
                run.resolved.insert(org.orgId)
            }
        }
        for org in run.state.orgs where org.status == .member {
            let id = org.orgId
            let org = run.state.org(id) ?? org
            // S1: fingerprint compare.
            if let new = incomingSeat(run, id) {
                if let old = org.seat, old.source == new.source, old.value != new.value, !run.identity.contains(id) {
                    run.emit(.seatChange(PairRef(profileId: run.profileId, orgId: id),
                                         from: old.value, to: new.value, inferred: false))
                    run.state.updateOrg(id) { $0.seat = new }
                    run.markIdentity(id)
                    run.state.updateOrg(id) { $0.pending = nil }
                    continue
                }
                run.state.updateOrg(id) {
                    $0.seat = new
                    if let p = $0.pending, case .seatInferred = p.kind { $0.pending = nil }
                }
                continue
            }
            // S2: inferred, only without any fingerprint.
            guard org.seat == nil, accepted.contains(id), !run.identity.contains(id),
                  let sample = run.obs.samples[id] else { continue }
            if let pending = org.pending, case .seatInferred = pending.kind {
                if run.now.timeIntervalSince(pending.detectedAt) <= pendingMaxAge,
                   settled(sample, near: pending.candidate) {
                    run.emit(.seatChange(PairRef(profileId: run.profileId, orgId: id),
                                         from: nil, to: nil, inferred: true))
                    run.markIdentity(id)
                } else {
                    run.state.updateOrg(id) { $0.pending = nil }
                    run.resolved.insert(id)
                }
                continue
            }
            if org.pending == nil, let prev = org.lastUsage, isSeatCandidate(prev, sample) {
                let at = run.now
                run.state.updateOrg(id) {
                    $0.pending = PendingChange(kind: .seatInferred, baseline: prev, candidate: sample, detectedAt: at)
                }
                run.resolved.insert(id)
            }
        }
    }

    private static func windows(_ prev: ClaudeUsage, _ new: ClaudeUsage) -> [(prev: Double, new: Double, weekly: Bool)] {
        var w: [(Double, Double, Bool)] = []
        if prev.hasSessionLimit && new.hasSessionLimit { w.append((prev.sessionPercentage, new.sessionPercentage, false)) }
        if prev.hasWeeklyLimit && new.hasWeeklyLimit { w.append((prev.weeklyPercentage, new.weeklyPercentage, true)) }
        // The API maps a null per-model window to 0.0, so 0 means absent, not a drop.
        if new.opusWeeklyPercentage > 0 { w.append((prev.opusWeeklyPercentage, new.opusWeeklyPercentage, false)) }
        if new.sonnetWeeklyPercentage > 0 { w.append((prev.sonnetWeeklyPercentage, new.sonnetWeeklyPercentage, false)) }
        return w.map { (prev: $0.0, new: $0.1, weekly: $0.2) }
    }

    private static func isSeatCandidate(_ prev: ClaudeUsage, _ new: ClaudeUsage) -> Bool {
        let tol = ResetDetection.tolerance
        if prev.hasSessionLimit && new.hasSessionLimit,
           abs(new.sessionResetTime.timeIntervalSince(prev.sessionResetTime)) > tol { return false }
        if prev.hasWeeklyLimit && new.hasWeeklyLimit,
           abs(new.weeklyResetTime.timeIntervalSince(prev.weeklyResetTime)) > tol { return false }
        let q = windows(prev, new).filter { $0.prev >= 5 }
        guard q.count >= 2, q.contains(where: { $0.weekly && abs($0.new - $0.prev) >= 3 }) else { return false }
        guard !q.contains(where: { $0.new <= 1 }) else { return false }
        let ratios = q.map { $0.new / $0.prev }
        let down = ratios.allSatisfy { $0 < 0.67 }
        let up = ratios.allSatisfy { $0 > 1.5 }
        guard down || up, let hi = ratios.max(), let lo = ratios.min() else { return false }
        return hi / lo <= 1.3
    }

    private static func settled(_ sample: ClaudeUsage, near cand: ClaudeUsage) -> Bool {
        windows(cand, sample).filter { $0.prev >= 1 }.allSatisfy {
            abs($0.new - $0.prev) <= 2 || abs($0.new - $0.prev) <= 0.25 * $0.prev
        }
    }

    // MARK: R - early reset

    private static func ruleR(_ run: inout Run) {
        let accepted = acceptedOrgIds(run)
        for org in run.state.orgs where org.status == .member && accepted.contains(org.orgId) {
            let id = org.orgId
            guard !run.identity.contains(id), !run.resolved.contains(id), let sample = run.obs.samples[id] else { continue }
            let ref = PairRef(profileId: run.profileId, orgId: id)

            if let pending = org.pending, case let .earlyReset(w) = pending.kind {
                guard run.now.timeIntervalSince(pending.detectedAt) <= pendingMaxAge,
                      present(w, pending.baseline, sample) else {
                    run.state.updateOrg(id) { $0.pending = nil }
                    continue
                }
                if value(w, sample) <= value(w, pending.baseline) * 0.5 {
                    run.emit(.earlyReset(ref, window: w, fromPercent: value(w, pending.baseline), toPercent: value(w, sample)))
                    run.result.resetSnapshots.append(ResetSnapshot(orgId: id, window: w, previous: pending.baseline))
                    run.markIdentity(id)
                } else {
                    run.state.updateOrg(id) { $0.pending = nil }
                }
                continue
            }
            guard org.pending == nil, let prev = org.lastUsage else { continue }
            for w in [UsageWindow.session, .weekly] where present(w, prev, sample) {
                let p = value(w, prev), n = value(w, sample)
                let natural = run.now >= resetTime(w, prev).addingTimeInterval(-ResetDetection.tolerance)
                if natural {
                    if ResetDetection.isReset(from: resetTime(w, prev), to: resetTime(w, sample)) {
                        run.result.resetSnapshots.append(ResetSnapshot(orgId: id, window: w, previous: prev))
                    }
                } else if p >= 10, n <= p * 0.5, p - n >= 10,
                          run.state.org(id)?.pending == nil {
                    let at = run.now
                    run.state.updateOrg(id) {
                        $0.pending = PendingChange(kind: .earlyReset(w), baseline: prev, candidate: sample, detectedAt: at)
                    }
                }
            }
        }
    }

    private static func present(_ w: UsageWindow, _ a: ClaudeUsage, _ b: ClaudeUsage) -> Bool {
        w == .session ? (a.hasSessionLimit && b.hasSessionLimit) : (a.hasWeeklyLimit && b.hasWeeklyLimit)
    }
    private static func value(_ w: UsageWindow, _ u: ClaudeUsage) -> Double {
        w == .session ? u.sessionPercentage : u.weeklyPercentage
    }
    private static func resetTime(_ w: UsageWindow, _ u: ClaudeUsage) -> Date {
        w == .session ? u.sessionResetTime : u.weeklyResetTime
    }

    // MARK: Accepted samples (shared by S and R; recorded once after both)

    private static func acceptedOrgIds(_ run: Run) -> Set<String> {
        Set(run.obs.samples.keys.filter { run.state.org($0)?.status == .member })
    }

    private static func recordSamples(_ run: inout Run) {
        let now = run.now
        for id in acceptedOrgIds(run) {
            guard let sample = run.obs.samples[id] else { continue }
            run.state.updateOrg(id) {
                $0.lastUsage = sample
                $0.lastSampleAt = now
            }
            run.result.acceptedSamples[id] = sample
        }
        if !run.result.acceptedSamples.isEmpty { run.state.consecutiveOAuthUnauthorized = 0 }
    }

    // MARK: X - old-team expiry

    private static func ruleX(_ run: inout Run) {
        let expired = run.state.orgs.filter {
            $0.status == .old && run.now.timeIntervalSince($0.lastSeenInListAt ?? $0.firstSeenAt) >= 15 * day
        }
        for org in expired {
            run.emit(.oldTeamDeleted(profileId: run.profileId, org: org.orgId, manual: false))
            run.state.orgs.removeAll { $0.orgId == org.orgId }
            run.result.deletedHistoryKeys.append(org.historyKey)
        }
    }
}
