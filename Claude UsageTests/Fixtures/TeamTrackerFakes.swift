import Foundation
@testable import Claude_Usage

/// Fakes for TeamTracker tests: fetcher, credentials, in-memory store, recording history and notifier.
final class FakeTeamFetcher: TeamUsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var lists: [String: Result<[ClaudeAPIService.AccountInfo], Error>] = [:]
    private var usages: [String: Result<ClaudeUsage, Error>] = [:]
    private var oauth: [UUID: Result<ClaudeUsage, Error>] = [:]
    private var _calls: [String] = []
    private var _blocked = false
    private var _release = true
    private var gateOAuth = false

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return _blocked }

    func callCount(prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }

    func setList(_ sessionKey: String, json: String) {
        let infos = (try? JSONDecoder().decode([ClaudeAPIService.AccountInfo].self, from: Data(json.utf8))) ?? []
        lock.lock(); lists[sessionKey] = .success(infos); lock.unlock()
    }
    func setList(_ sessionKey: String, error: Error) { lock.lock(); lists[sessionKey] = .failure(error); lock.unlock() }
    func setUsage(_ sessionKey: String, org: String, _ usage: ClaudeUsage) {
        lock.lock(); usages["\(sessionKey)|\(org)"] = .success(usage); lock.unlock()
    }
    func setUsage(_ sessionKey: String, org: String, error: Error) {
        lock.lock(); usages["\(sessionKey)|\(org)"] = .failure(error); lock.unlock()
    }
    /// A provider reading. `lastUpdated` defaults to a fresh fetch (after any test clock); pass an older
    /// date to model the provider's fall-back to a cached reading.
    func setOAuth(_ id: UUID, _ usage: ClaudeUsage, lastUpdated: Date = .distantFuture) {
        var u = usage
        u.lastUpdated = lastUpdated
        lock.lock(); oauth[id] = .success(u); lock.unlock()
    }
    func blockOAuth() { lock.lock(); gateOAuth = true; _release = false; lock.unlock() }
    func releaseOAuth() { lock.lock(); _release = true; lock.unlock() }

    private func log(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }

    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo] {
        log("list:\(sessionKey)")
        lock.lock(); let r = lists[sessionKey]; lock.unlock()
        return try (r ?? .failure(AppError(code: .apiGenericError, message: "no list"))).get()
    }

    func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        log("usage:\(sessionKey)|\(organizationId)")
        lock.lock(); let r = usages["\(sessionKey)|\(organizationId)"]; lock.unlock()
        return try (r ?? .success(FakeTeamFetcher.zero)).get()
    }

    func fetchUsageViaProvider(_ profile: Profile) async throws -> ClaudeUsage {
        log("oauth:\(profile.id.uuidString)")
        lock.lock(); let gated = gateOAuth; if gated { _blocked = true }; lock.unlock()
        while gated {
            lock.lock(); let go = _release; lock.unlock()
            if go { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        lock.lock(); let r = oauth[profile.id]; lock.unlock()
        return try (r ?? .success(FakeTeamFetcher.zero)).get()
    }

    static let zero: ClaudeUsage = (try? TeamFixtures.usage(session: 0, weekly: 0)) ?? .empty
}

final class FakeTeamCredentials: TeamCredentialReading {
    var fingerprints: [UUID: String] = [:]
    func sessionKey(for p: Profile) -> String? { p.claudeSessionKey }
    func hasCredential(_ p: Profile) -> Bool { p.claudeSessionKey != nil || p.cliCredentialsJSON != nil }
    func credentialOrg(for p: Profile) -> (orgId: String?, seat: SeatFingerprint?) {
        (CredentialOrgParser.orgId(fromCredentialsJSON: p.cliCredentialsJSON), nil)
    }
    func fingerprint(for p: Profile) -> String? { fingerprints[p.id] }
}

@MainActor
final class FakeTeamStore: TeamProfileStore {
    var profiles: [Profile] = []
    var activeProfileId: UUID?
    var trackingWrites = 0
    var savedUsage: [(UUID, ClaudeUsage)] = []
    var orgIdWrites: [(UUID, String?)] = []
    var trackedProfiles: [Profile] { profiles }

    func profile(_ id: UUID) -> Profile { profiles.first { $0.id == id }! }
    private func index(_ id: UUID) -> Int? { profiles.firstIndex { $0.id == id } }

    func updateOrgTracking(_ s: OrgTrackingState, for id: UUID) {
        guard let i = index(id) else { return }
        trackingWrites += 1
        profiles[i].orgTracking = s
    }
    func updateOrganizationId(_ o: String?, for id: UUID) {
        guard let i = index(id) else { return }
        orgIdWrites.append((id, o))
        profiles[i].organizationId = o
    }
    func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID) {
        guard let i = index(id) else { return }
        savedUsage.append((id, u))
        profiles[i].claudeUsage = u
    }
}

@MainActor
final class FakeTeamHistory: PairHistoryRecording {
    var sessionPeriodic: [String] = []
    var weeklyPeriodic: [String] = []
    var sessionResets: [(key: String, previous: ClaudeUsage?)] = []
    var weeklyResets: [String] = []
    var deleted: [String] = []
    func recordSessionPeriodic(forKey key: String, usage: ClaudeUsage, provider: Provider) { sessionPeriodic.append(key) }
    func recordWeeklyPeriodic(forKey key: String, usage: ClaudeUsage, provider: Provider) { weeklyPeriodic.append(key) }
    func recordSessionReset(forKey key: String, previousUsage: ClaudeUsage?, resetTime: Date, provider: Provider) {
        sessionResets.append((key, previousUsage))
    }
    func recordWeeklyReset(forKey key: String, previousUsage: ClaudeUsage?, resetTime: Date, provider: Provider) {
        weeklyResets.append(key)
    }
    func deleteHistory(forKey key: String) { deleted.append(key) }
}

@MainActor
final class FakeTeamNotifier: TeamEventNotifying {
    var posted: [TeamEvent] = []
    func post(_ event: TeamEvent, profiles: [Profile]) { posted.append(event) }
}

final class ClockBox: @unchecked Sendable { var now: Date; init(_ d: Date) { now = d } }
