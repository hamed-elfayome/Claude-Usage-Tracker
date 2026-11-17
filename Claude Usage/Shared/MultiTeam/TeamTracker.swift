import Foundation
import Combine

// The follow-the-account tracker (docs/specs/multi-team-tracking.md §3-§7, §10, §12).
// Every network, credential, storage, history and notification dependency is a protocol so tests use fakes.

protocol TeamUsageFetching: Sendable {
    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo]
    func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage
    func fetchUsageViaProvider(_ profile: Profile) async throws -> ClaudeUsage   // OAuth-only probes
}

protocol TeamCredentialReading {
    func sessionKey(for p: Profile) -> String?
    func hasCredential(_ p: Profile) -> Bool
    func credentialOrg(for p: Profile) -> (orgId: String?, seat: SeatFingerprint?)
    func fingerprint(for p: Profile) -> String?
}

@MainActor
protocol TeamProfileStore {
    var trackedProfiles: [Profile] { get }
    var activeProfileId: UUID? { get }
    func updateOrgTracking(_ s: OrgTrackingState, for id: UUID)
    func updateOrganizationId(_ o: String?, for id: UUID)
    func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID)
}

@MainActor
protocol PairHistoryRecording {
    func recordSessionPeriodic(forKey key: String, usage: ClaudeUsage, provider: Provider)
    func recordWeeklyPeriodic(forKey key: String, usage: ClaudeUsage, provider: Provider)
    func recordSessionReset(forKey key: String, previousUsage: ClaudeUsage?, resetTime: Date, provider: Provider)
    func recordWeeklyReset(forKey key: String, previousUsage: ClaudeUsage?, resetTime: Date, provider: Provider)
    func deleteHistory(forKey key: String)
}

@MainActor
protocol TeamEventNotifying {
    func post(_ event: TeamEvent, profiles: [Profile])
}

@MainActor
final class TeamTracker: ObservableObject {
    static let shared = TeamTracker(
        store: ProfileManager.shared, fetcher: ClaudeAPITeamFetcher(), credentials: StoredCredentialReader(),
        history: UsageHistoryService.shared, notifier: NoopTeamEventNotifier(), globalStore: TeamTrackingGlobalStore())

    var notifier: TeamEventNotifying
    var onCurrentChanged: ((PairRef?) -> Void)?
    var onSample: ((UUID, ClaudeUsage) -> Void)?
    @Published private(set) var global: TeamTrackingGlobalState

    private let store: TeamProfileStore
    private let fetcher: TeamUsageFetching
    private let credentials: TeamCredentialReading
    private let history: PairHistoryRecording
    private let globalStore: TeamTrackingGlobalStore
    private let policy: PollPolicy
    private let clock: () -> Date
    private let isEnabled: () -> Bool
    private let runsLoop: Bool
    private var scheduler: TeamPollScheduler
    private var lastSavedGlobal: TeamTrackingGlobalState
    private var started = false
    private var generation = 0
    private var isTicking = false
    private var registeredOrgList: [UUID: Bool] = [:]
    private var loop: Task<Void, Never>?
    /// The last background forced-list task (a live membership failure); tests await it.
    private(set) var backgroundTask: Task<Void, Never>?

    private enum Source { case probe, live, list }
    private struct ListItem: Sendable { let profileId: UUID; let sessionKey: String }
    private struct ProbeItem: Sendable { let profile: Profile; let orgId: String; let sessionKey: String?; let lastSampleAt: Date? }
    private struct GroupJob { let trigger: UUID; let orgId: String; let target: String? }
    private static let switchNotificationGap: TimeInterval = 900

    init(store: TeamProfileStore, fetcher: TeamUsageFetching, credentials: TeamCredentialReading,
         history: PairHistoryRecording, notifier: TeamEventNotifying, globalStore: TeamTrackingGlobalStore,
         policy: PollPolicy = .default, clock: @escaping () -> Date = { Date() },
         random: @escaping () -> Double = { Double.random(in: 0..<1) },
         isEnabled: @escaping () -> Bool = { TeamTrackingSettings.isEnabled() }, runsLoop: Bool = true) {
        self.store = store
        self.fetcher = fetcher
        self.credentials = credentials
        self.history = history
        self.notifier = notifier
        self.globalStore = globalStore
        self.policy = policy
        self.clock = clock
        self.isEnabled = isEnabled
        self.runsLoop = runsLoop
        self.scheduler = TeamPollScheduler(policy: policy, random: random)
        let loaded = globalStore.load()
        self.global = loaded
        self.lastSavedGlobal = loaded
    }

    // MARK: Lifecycle

    var isRunning: Bool { started && isEnabled() }

    func start() {
        guard isEnabled(), !started else { return }
        started = true
        scheduler.start(now: clock())
        guard runsLoop else { return }
        let nanos = UInt64(max(0, min(policy.tick, 3600)) * 1_000_000_000)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick(now: self.clock())
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        started = false
        generation += 1
        loop?.cancel()
        loop = nil
    }

    // MARK: Contract used by the menu bar loop

    func liveTarget() -> (profile: Profile, orgId: String)? {
        guard isRunning, let cur = global.current, let p = trackedProfile(cur.profileId),
              let state = p.orgTracking, state.authState == .ok,
              state.org(cur.orgId)?.status == .member,
              !scheduler.isBackingOff(p.id, now: clock()) else { return nil }
        return (p, cur.orgId)
    }

    func ingestLive(profileId: UUID, orgId: String, result: Result<ClaudeUsage, Error>, isCachedReading: Bool) {
        guard isRunning, let p = trackedProfile(profileId), p.orgTracking?.org(orgId) != nil else { return }
        let now = clock()
        var obs = baseObservation(p, now: now)
        let hasKey = obs.hasSessionKey
        switch result {
        case .success(let usage):
            guard !isCachedReading else { return }
            scheduler.record(accountId: profileId, outcome: .success, now: now)
            obs.samples = [orgId: usage]
        case .failure(let error):
            guard let e = error as? AppError else { return }
            if e.isCloudflareChallenge { return }
            if e.isRateLimited {
                scheduler.record(accountId: profileId, outcome: .rateLimited(retryAfter: e.retryAfterSeconds), now: now)
                return
            }
            scheduler.record(accountId: profileId, outcome: .failed, now: now)
            guard e.isMembershipFailure else { return }
            if hasKey {
                obs.usageMembershipFailures = [orgId]
            } else if e.code == .apiUnauthorized {
                obs.oauthUnauthorized = true
            } else {
                return
            }
        }
        let applied = apply(obs, profileId: profileId, source: .live, withholding: [], allowGroup: true)
        persistGlobal()
        let gen = generation
        if let applied, !applied.jobs.isEmpty {
            backgroundTask = Task { [weak self] in await self?.runGroupMoves(applied.jobs, now: now, gen: gen) }
        } else if hasKey, !obs.usageMembershipFailures.isEmpty {
            backgroundTask = Task { [weak self] in await self?.forcedLists([profileId], now: now, gen: gen) }
        }
    }

    func makeCurrent(_ pair: PairRef) {
        let now = clock()
        // Same conditions as liveTarget(): only a pair that can be live may become current.
        guard isRunning, pair != global.current, let p = trackedProfile(pair.profileId),
              let state = p.orgTracking, state.authState == .ok,
              state.org(pair.orgId)?.status == .member,
              !scheduler.isBackingOff(p.id, now: now) else { return }
        global.manualPickAt = now
        moveCurrent(to: pair, manual: true, now: now)
        persistGlobal()
    }

    func deleteOldPair(_ pair: PairRef) -> Bool {
        guard let p = trackedProfile(pair.profileId), var state = p.orgTracking,
              let org = state.org(pair.orgId), org.status == .old || org.status == .unreachable else { return false }
        state.orgs.removeAll { $0.orgId == pair.orgId }
        store.updateOrgTracking(state, for: p.id)
        history.deleteHistory(forKey: org.historyKey)
        if global.current == pair {
            global.current = nil
            onCurrentChanged?(nil)
        }
        record(TeamEvent(kind: .oldTeamDeleted(profileId: p.id, org: pair.orgId, manual: true),
                         names: names([p.id]).merging([pair.orgId: org.name]) { a, _ in a }, date: clock()), now: clock())
        persistGlobal()
        return true
    }

    func reportRefreshRejected(profileId: UUID) {
        guard isRunning, let p = trackedProfile(profileId) else { return }
        var obs = baseObservation(p, now: clock())
        obs.refreshRejected = true
        apply(obs, profileId: profileId, source: .live, withholding: [], allowGroup: false)
        persistGlobal()
    }

    // MARK: Tick

    func tick(now: Date) async {
        guard isRunning, !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        let gen = generation
        syncAccounts(now: now)
        guard !store.trackedProfiles.isEmpty else { return }
        repairCurrent()
        await runDueLists(now: now, gen: gen)
        guard gen == generation else { return }
        if scheduler.isRoundDue(now: now) { await runRound(now: now, gen: gen) }
        guard gen == generation else { return }
        persistGlobal()
    }

    private func syncAccounts(now: Date) {
        let profiles = store.trackedProfiles
        let ids = Set(profiles.map(\.id))
        for p in profiles {
            // The scheduler keeps hasOrgList from the first register, so a session key that appears or
            // goes away re-registers the account (unregister is a no-op for a new one). This also clears
            // its 429 backoff on purpose: the key change moves it to another request path.
            let hasKey = credentials.sessionKey(for: p) != nil
            if registeredOrgList[p.id] != hasKey {
                scheduler.unregister(accountId: p.id)
                scheduler.register(accountId: p.id, hasOrgList: hasKey, now: now)
                registeredOrgList[p.id] = hasKey
            }
            if p.orgTracking == nil, let s = TeamTrackingMigration.migrate(p, now: now).orgTracking {
                store.updateOrgTracking(s, for: p.id)
            }
        }
        for id in scheduler.registeredAccounts where !ids.contains(id) {
            scheduler.unregister(accountId: id)
            registeredOrgList[id] = nil
        }
    }

    /// Start rule (§4): current nil or pointing at a deleted profile/pair becomes the active profile's followed pair.
    private func repairCurrent() {
        if let cur = global.current, trackedProfile(cur.profileId)?.orgTracking?.org(cur.orgId) != nil { return }
        var next: PairRef?
        if let id = store.activeProfileId, let p = trackedProfile(id), let state = p.orgTracking {
            let orgId = p.organizationId.flatMap { state.org($0) != nil ? $0 : nil }
                ?? state.orgs.first { $0.status == .member }?.orgId
            next = orgId.map { PairRef(profileId: id, orgId: $0) }
        }
        guard next != global.current else { return }
        global.current = next
        onCurrentChanged?(next)
    }

    // MARK: Org lists

    private func fetchLists(_ items: [ListItem], timeout: TimeInterval? = nil) async -> [(ListItem, Result<[ClaudeAPIService.AccountInfo], Error>?)] {
        let fetcher = self.fetcher
        return await BoundedTaskRunner.run(items, key: { $0.profileId }, maxConcurrent: policy.maxConcurrent,
                                           maxPerKey: policy.maxPerAccount, timeout: timeout) { item in
            do { return .success(try await fetcher.fetchOrganizations(sessionKey: item.sessionKey)) } catch { return .failure(error) }
        }
    }

    private func listItem(_ id: UUID) -> ListItem? {
        guard let p = trackedProfile(id), p.orgTracking?.authState == .ok,
              let key = credentials.sessionKey(for: p) else { return nil }
        return ListItem(profileId: id, sessionKey: key)
    }

    /// Feeds the scheduler and returns the observation for this list result, or nil when no rule may run.
    private func listObservation(_ p: Profile, _ result: Result<[ClaudeAPIService.AccountInfo], Error>?, now: Date) -> AccountObservation? {
        guard let result else {
            scheduler.listFinished(accountId: p.id, outcome: .failed, now: now)
            return nil
        }
        var obs = baseObservation(p, now: now)
        switch result {
        case .success(let infos):
            scheduler.listFinished(accountId: p.id, outcome: .success, now: now)
            obs.orgList = infos.map {
                OrgListEntry(orgId: $0.uuid, name: $0.name,
                             seat: CredentialOrgParser.seat(rateLimitTier: $0.rateLimitTier, ravenType: $0.ravenType, billingType: $0.billingType),
                             canChat: $0.capabilities.contains("chat"))
            }
            return obs
        case .failure(let error):
            guard let e = error as? AppError, !e.isCloudflareChallenge else {
                scheduler.listFinished(accountId: p.id, outcome: .failed, now: now)
                return nil
            }
            if e.isRateLimited {
                scheduler.listFinished(accountId: p.id, outcome: .rateLimited(retryAfter: e.retryAfterSeconds), now: now)
                return nil
            }
            scheduler.listFinished(accountId: p.id, outcome: .failed, now: now)
            guard e.code == .apiUnauthorized else { return nil }
            obs.orgListAuthFailed = true
            return obs
        }
    }

    private func runDueLists(now: Date, gen: Int) async {
        let items = scheduler.dueLists(now: now).compactMap(listItem)
        guard !items.isEmpty else { return }
        let results = await fetchLists(items)
        guard gen == generation else { return }
        for (item, res) in results {
            guard let p = trackedProfile(item.profileId), let obs = listObservation(p, res, now: now) else { continue }
            await applyAndRun(obs, profileId: p.id, source: .list, now: now, gen: gen)
        }
    }

    private func forcedLists(_ ids: [UUID], now: Date, gen: Int) async {
        let items = ids.compactMap { id -> ListItem? in
            guard let item = listItem(id), scheduler.forceList(accountId: id, now: now) else { return nil }
            return item
        }
        guard !items.isEmpty else { return }
        let results = await fetchLists(items)
        guard gen == generation else { return }
        for (item, res) in results {
            guard let p = trackedProfile(item.profileId), let obs = listObservation(p, res, now: now) else { continue }
            await applyAndRun(obs, profileId: p.id, source: .list, now: now, gen: gen)
        }
        persistGlobal()
    }

    // MARK: Probe round

    private struct Gathered {
        var samples: [String: ClaudeUsage] = [:]
        var failures: Set<String> = []
        var unauthorized = false
    }

    private func runRound(now: Date, gen: Int) async {
        scheduler.roundStarted(now: now)
        var items: [ProbeItem] = []
        for p in store.trackedProfiles {
            guard let state = p.orgTracking, state.authState == .ok, !scheduler.isBackingOff(p.id, now: now) else { continue }
            func eligible(_ o: TrackedOrg) -> Bool {
                o.status == .member && o.orgId != TrackedOrg.unknownOrgId && global.current != PairRef(profileId: p.id, orgId: o.orgId)
            }
            if let key = credentials.sessionKey(for: p) {
                for o in state.orgs where eligible(o) {
                    items.append(ProbeItem(profile: p, orgId: o.orgId, sessionKey: key, lastSampleAt: o.lastSampleAt))
                }
            } else if credentials.hasCredential(p),
                      let orgId = credentials.credentialOrg(for: p).orgId ?? state.credentialOrgId,
                      let o = state.org(orgId), eligible(o) {
                items.append(ProbeItem(profile: p, orgId: orgId, sessionKey: nil, lastSampleAt: o.lastSampleAt))
            }
        }
        let fetcher = self.fetcher
        let results = await BoundedTaskRunner.run(items, key: { $0.profile.id }, maxConcurrent: policy.maxConcurrent,
                                                  maxPerKey: policy.maxPerAccount) { item -> Result<ClaudeUsage, Error> in
            do {
                if let key = item.sessionKey {
                    return .success(try await fetcher.fetchUsageOnly(sessionKey: key, organizationId: item.orgId))
                }
                return .success(try await fetcher.fetchUsageViaProvider(item.profile))
            } catch { return .failure(error) }
        }
        guard gen == generation else { return }

        var gathered: [UUID: Gathered] = [:]
        for (item, res) in results {
            guard let res else { continue }
            let id = item.profile.id
            switch res {
            case .success(let usage):
                // A provider fall-back to the cached reading carries an old lastUpdated: that is no sample.
                // With no sample yet, anything older than one round counts as cached.
                if item.sessionKey == nil,
                   usage.lastUpdated <= (item.lastSampleAt ?? now.addingTimeInterval(-policy.roundInterval)) { continue }
                gathered[id, default: Gathered()].samples[item.orgId] = usage
                scheduler.record(accountId: id, outcome: .success, now: now)
            case .failure(let error):
                guard let e = error as? AppError else {
                    scheduler.record(accountId: id, outcome: .failed, now: now)
                    continue
                }
                if e.isCloudflareChallenge { continue }
                if e.isRateLimited {
                    scheduler.record(accountId: id, outcome: .rateLimited(retryAfter: e.retryAfterSeconds), now: now)
                    continue
                }
                scheduler.record(accountId: id, outcome: .failed, now: now)
                if e.isMembershipFailure {
                    if item.sessionKey != nil { gathered[id, default: Gathered()].failures.insert(item.orgId) }
                    else if e.code == .apiUnauthorized { gathered[id, default: Gathered()].unauthorized = true }
                }
            }
        }

        var needList: [UUID] = []
        for p in store.trackedProfiles {
            guard let current = trackedProfile(p.id), current.orgTracking != nil else { continue }
            let g = gathered[p.id] ?? Gathered()
            var obs = baseObservation(current, now: now)
            obs.samples = g.samples
            obs.usageMembershipFailures = g.failures
            obs.oauthUnauthorized = g.unauthorized
            await applyAndRun(obs, profileId: p.id, source: .probe, now: now, gen: gen)
            guard gen == generation else { return }
            if !g.failures.isEmpty { needList.append(p.id) }
        }
        await forcedLists(needList, now: now, gen: gen)
        guard gen == generation else { return }
        detect(now: now)
    }

    private func detect(now: Date) {
        let lastRound = global.lastRoundAt ?? .distantPast
        var candidates: [RoundCandidate] = []
        for p in store.trackedProfiles {
            guard let state = p.orgTracking, state.authState == .ok else { continue }
            for o in state.orgs where o.status == .member {
                let fresh = (o.lastSampleAt.map { $0 > lastRound } ?? false) && o.lastUsage != nil
                candidates.append(RoundCandidate(pair: PairRef(profileId: p.id, orgId: o.orgId), previous: o.roundReading,
                                                 latest: fresh ? o.lastUsage : nil, latestAt: fresh ? o.lastSampleAt : nil))
            }
        }
        let out = CurrentPairDetector.evaluate(RoundInput(
            now: now, current: global.current, manualPickAt: global.manualPickAt,
            lastRoundAt: global.lastRoundAt, candidates: candidates))
        let byProfile = Dictionary(grouping: out.readings.keys, by: \.profileId)
        for (id, refs) in byProfile {
            guard var state = trackedProfile(id)?.orgTracking else { continue }
            for ref in refs { state.updateOrg(ref.orgId) { $0.roundReading = out.readings[ref] } }
            store.updateOrgTracking(state, for: id)
        }
        global.lastRoundAt = now
        if out.clearManualPick { global.manualPickAt = nil }
        if out.switched, let next = out.current { moveCurrent(to: next, manual: false, now: now) }
    }

    /// Switch effects (§4), shared by detection and the manual pick.
    private func moveCurrent(to pair: PairRef, manual: Bool, now: Date) {
        let old = global.current
        global.current = pair
        if let p = trackedProfile(pair.profileId) {
            if credentials.sessionKey(for: p) != nil { store.updateOrganizationId(pair.orgId, for: p.id) }
            if let u = p.orgTracking?.org(pair.orgId)?.lastUsage { store.saveClaudeUsage(u, for: p.id) }
        }
        let ids = [pair.profileId] + (old.map { [$0.profileId] } ?? [])
        record(TeamEvent(kind: .nowOn(pair, from: old, manual: manual), names: names(ids), date: now), now: now)
        onCurrentChanged?(pair)
    }

    // MARK: Rules, persistence, events

    private func baseObservation(_ p: Profile, now: Date) -> AccountObservation {
        var obs = AccountObservation(now: now)
        obs.hasSessionKey = credentials.sessionKey(for: p) != nil
        obs.credentialFingerprint = credentials.fingerprint(for: p)
        let c = credentials.credentialOrg(for: p)
        obs.credentialOrgId = c.orgId
        obs.credentialSeat = c.seat
        return obs
    }

    private func applyAndRun(_ obs: AccountObservation, profileId: UUID, source: Source, now: Date, gen: Int) async {
        guard let applied = apply(obs, profileId: profileId, source: source, withholding: [], allowGroup: true) else { return }
        await runGroupMoves(applied.jobs, now: now, gen: gen)
    }

    @discardableResult
    private func apply(_ obs: AccountObservation, profileId: UUID, source: Source, withholding: Set<String>,
                       allowGroup: Bool) -> (result: AccountResult, jobs: [GroupJob])? {
        guard let p = trackedProfile(profileId) else { return nil }   // deleted while a request was in flight
        let state = p.orgTracking ?? TeamTrackingMigration.migrate(p, now: obs.now).orgTracking ?? .empty
        let result = AccountRules.apply(obs, to: state, profileId: profileId, profileName: p.name, followedOrgId: p.organizationId)
        var withheld = withholding
        var jobs: [GroupJob] = []
        if allowGroup {
            for r in result.confirmedRemovals where !peers(of: profileId, losing: r.orgId).isEmpty {
                jobs.append(GroupJob(trigger: profileId, orgId: r.orgId, target: r.movedTo))
                withheld.insert(r.orgId)
            }
        }
        process(p, result, source: source, withholding: withheld, now: obs.now)
        return (result, jobs)
    }

    private func process(_ p: Profile, _ r: AccountResult, source: Source, withholding: Set<String>, now: Date) {
        let id = p.id
        store.updateOrgTracking(r.state, for: id)
        if let f = r.followedOrgId {
            if credentials.sessionKey(for: p) != nil { store.updateOrganizationId(f, for: id) }
            if let u = r.state.org(f)?.lastUsage { store.saveClaudeUsage(u, for: id) }
        }
        var skip = Set<String>()
        for s in r.resetSnapshots {
            guard let key = r.state.org(s.orgId)?.historyKey else { continue }
            switch s.window {
            case .session: history.recordSessionReset(forKey: key, previousUsage: s.previous, resetTime: s.previous.sessionResetTime, provider: .anthropic)
            case .weekly: history.recordWeeklyReset(forKey: key, previousUsage: s.previous, resetTime: s.previous.weeklyResetTime, provider: .anthropic)
            }
            skip.insert("\(s.orgId)|\(s.window.rawValue)")
        }
        for orgId in r.acceptedSamples.keys.sorted() {
            guard let usage = r.acceptedSamples[orgId], let key = r.state.org(orgId)?.historyKey else { continue }
            if !skip.contains("\(orgId)|session") { history.recordSessionPeriodic(forKey: key, usage: usage, provider: .anthropic) }
            if !skip.contains("\(orgId)|weekly") { history.recordWeeklyPeriodic(forKey: key, usage: usage, provider: .anthropic) }
        }
        for key in r.deletedHistoryKeys { history.deleteHistory(forKey: key) }

        // Invariant 3: a probe sample of the followed org of a non-current account is that account's claudeUsage.
        // An OAuth-only account follows its credential org (rule T, the org its probe asked for): its
        // organizationId belongs to the claude.ai credentials, so it is nil and the tracker never writes it.
        if source != .live, global.current?.profileId != id,
           let followed = r.followedOrgId ?? (credentials.sessionKey(for: p) != nil ? p.organizationId : r.state.credentialOrgId),
           let u = r.acceptedSamples[followed] {
            store.saveClaudeUsage(u, for: id)
            onSample?(id, u)
        }

        for e in r.events {
            switch e.kind {
            case let .adminMove(pid, from, _) where pid == id && withholding.contains(from): continue
            case let .teamRemoved(pid, org) where pid == id && withholding.contains(org): continue
            default: record(e, now: now)
            }
        }

        if let cur = global.current, cur.profileId == id {
            let status = r.state.org(cur.orgId)?.status
            if status == .old || status == .unreachable {
                let target = status == .old ? r.confirmedRemovals.first { $0.orgId == cur.orgId }?.movedTo : r.followedOrgId
                global.current = target.map { PairRef(profileId: id, orgId: $0) }
                onCurrentChanged?(global.current)
            }
        }
    }

    private func record(_ e: TeamEvent, now: Date) {
        global.appendEvent(e)
        var post = e.notifies
        if case let .nowOn(_, _, manual) = e.kind, !manual {
            if let last = global.lastSwitchNotificationAt, now.timeIntervalSince(last) < Self.switchNotificationGap {
                post = false
            } else {
                global.lastSwitchNotificationAt = now
            }
        }
        guard post else { return }
        let ids = Set(involvedIds(e.kind))
        notifier.post(e, profiles: store.trackedProfiles.filter { ids.contains($0.id) })
    }

    private func involvedIds(_ k: TeamEvent.Kind) -> [UUID] {
        switch k {
        case let .nowOn(ref, from, _): return [ref.profileId] + (from.map { [$0.profileId] } ?? [])
        case let .adminMove(id, _, _), let .teamRemoved(id, _), let .teamChanged(id, _, _), let .teamAdded(id, _),
             let .teamRejoined(id, _), let .loginLost(id, _), let .oldTeamDeleted(id, _, _): return [id]
        case let .loginRestored(id): return [id]
        case let .groupMove(_, _, moves, notMoved, unchecked): return Array(moves.keys) + notMoved + unchecked
        case let .seatChange(ref, _, _, _), let .earlyReset(ref, _, _, _): return [ref.profileId]
        }
    }

    private func names(_ ids: [UUID]) -> [String: String] {
        var out: [String: String] = [:]
        for id in ids {
            guard let p = trackedProfile(id) else { continue }
            out[id.uuidString] = p.name
            for o in p.orgTracking?.orgs ?? [] { out[o.orgId] = o.name }
        }
        return out
    }

    private func trackedProfile(_ id: UUID) -> Profile? { store.trackedProfiles.first { $0.id == id } }

    private func persistGlobal() {
        guard global != lastSavedGlobal else { return }
        globalStore.save(global)
        lastSavedGlobal = global
    }

    // MARK: Group move (§6)

    private func peers(of trigger: UUID, losing orgId: String) -> [Profile] {
        store.trackedProfiles.filter {
            $0.id != trigger && $0.orgTracking?.authState == .ok && credentials.sessionKey(for: $0) != nil
                && $0.orgTracking?.org(orgId)?.status == .member
        }
    }

    private func runGroupMoves(_ jobs: [GroupJob], now: Date, gen: Int) async {
        for job in jobs {
            guard gen == generation else { return }
            await runGroupMove(job, now: now, gen: gen)
        }
    }

    private func runGroupMove(_ job: GroupJob, now: Date, gen: Int) async {
        let a = job.orgId
        var outcomes: [UUID: PeerOutcome] = [:]
        var items: [ListItem] = []
        for p in peers(of: job.trigger, losing: a) {
            if let item = listItem(p.id), scheduler.forceList(accountId: p.id, now: now, bypassDebounce: true) {
                items.append(item)
            } else {
                outcomes[p.id] = .unchecked
            }
        }
        let results = await fetchLists(items, timeout: 60)
        guard gen == generation else { return }
        for (item, res) in results {
            let id = item.profileId
            guard let p = trackedProfile(id), var obs = listObservation(p, res, now: now) else {
                outcomes[id] = .unchecked
                continue
            }
            if obs.orgListAuthFailed {
                // Same rule-L effect as runDueLists; the peer's removal stays unconfirmed.
                apply(obs, profileId: id, source: .list, withholding: [], allowGroup: false)
                outcomes[id] = .unchecked
                continue
            }
            guard !(obs.orgList ?? []).isEmpty else {
                outcomes[id] = .unchecked
                continue
            }
            obs.peerConfirmedRemovals = [a]
            guard let applied = apply(obs, profileId: id, source: .list, withholding: [a], allowGroup: false) else {
                outcomes[id] = .unchecked
                continue
            }
            if case .needsLogin = applied.result.state.authState {
                outcomes[id] = .unchecked
            } else if applied.result.state.org(a)?.status == .old {
                outcomes[id] = .moved(to: applied.result.confirmedRemovals.first { $0.orgId == a }?.movedTo)
            } else {
                outcomes[id] = .notMoved
            }
        }
        let event = GroupMoveAggregator.event(from: a, trigger: job.trigger, triggerTarget: job.target, peers: outcomes,
                                              names: names([job.trigger] + Array(outcomes.keys)), now: now)
        record(event, now: now)
    }
}
