import Foundation

// Data model for multi-team tracking (docs/specs/multi-team-tracking.md §3).

enum UsageWindow: String, Codable { case session, weekly }

struct SeatFingerprint: Codable, Equatable {
    enum Source: String, Codable { case orgList, credentials }
    let source: Source
    let value: String              // "|"-joined present values
}

enum PairStatus: String, Codable {
    case member        // in the org list (session key) or the credential org (OAuth-only)
    case old           // confirmed gone from the list: read-only, never probed, auto-deleted after 15 days
    case unreachable   // OAuth-only: a previous credential org; read-only, never probed, never auto-deleted
}

struct RoundReading: Codable, Equatable {
    let percent: Double
    let resetTime: Date
    let at: Date
}

struct PendingChange: Codable, Equatable {
    enum Kind: Codable, Equatable { case earlyReset(UsageWindow), seatInferred }
    let kind: Kind
    let baseline: ClaudeUsage
    let candidate: ClaudeUsage
    let detectedAt: Date
}

struct TrackedOrg: Codable, Equatable, Identifiable {
    var id: String { orgId }
    var orgId: String                 // TrackedOrg.unknownOrgId until known
    var name: String
    var status: PairStatus
    let historyKey: String            // assigned once, never reused
    var seat: SeatFingerprint?
    var lastUsage: ClaudeUsage?       // last real reading (never a projection)
    var lastSampleAt: Date?
    var firstSeenAt: Date
    var lastSeenInListAt: Date?
    var missingFromListCount: Int
    var lastMembershipFailureAt: Date?
    var pending: PendingChange?
    var baselineStartedAt: Date
    var roundReading: RoundReading?   // detection baseline (§4)
    static let unknownOrgId = "unknown-org"
}

enum AuthState: Codable, Equatable { case ok; case needsLogin(reason: String, since: Date) }

/// Per-account tracking state, stored on `Profile`.
struct OrgTrackingState: Codable, Equatable {
    var orgs: [TrackedOrg]
    var lastOrgListAt: Date?
    var authState: AuthState
    var legacyHistoryKeyAssigned: Bool
    var credentialOrgId: String?       // OAuth-only accounts: last seen token org
    var credentialFingerprint: String? // SHA256 prefix of session key + refresh token; never logged
    var consecutiveOAuthUnauthorized: Int

    static let empty = OrgTrackingState(
        orgs: [], lastOrgListAt: nil, authState: .ok, legacyHistoryKeyAssigned: false,
        credentialOrgId: nil, credentialFingerprint: nil, consecutiveOAuthUnauthorized: 0)

    func org(_ id: String) -> TrackedOrg? { orgs.first { $0.orgId == id } }

    mutating func updateOrg(_ id: String, _ body: (inout TrackedOrg) -> Void) {
        guard let i = orgs.firstIndex(where: { $0.orgId == id }) else { return }
        body(&orgs[i])
    }
}

struct PairRef: Codable, Hashable {
    let profileId: UUID
    let orgId: String
}

struct TeamEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case nowOn(PairRef, from: PairRef?, manual: Bool)
        case adminMove(profileId: UUID, from: String, to: String)
        case groupMove(from: String, to: String?, moves: [UUID: String?], notMoved: [UUID], unchecked: [UUID])
        case teamRemoved(profileId: UUID, org: String)
        case teamChanged(profileId: UUID, from: String, to: String)   // OAuth-only account
        case teamAdded(profileId: UUID, org: String)
        case teamRejoined(profileId: UUID, org: String)
        case seatChange(PairRef, from: String?, to: String?, inferred: Bool)
        case earlyReset(PairRef, window: UsageWindow, fromPercent: Double, toPercent: Double)
        case loginLost(profileId: UUID, reason: String)
        case loginRestored(profileId: UUID)
        case oldTeamDeleted(profileId: UUID, org: String, manual: Bool)
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let names: [String: String]       // orgId and profile uuidString -> display name at event time

    init(kind: Kind, names: [String: String], date: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.kind = kind
        self.names = names
    }

    private func name(_ id: String) -> String { names[id] ?? String(id.prefix(8)) }
    private func account(_ id: UUID) -> String { name(id.uuidString) }
    private func windowName(_ w: UsageWindow) -> String {
        (w == .session ? "multiteam.window.session" : "multiteam.window.weekly").localized
    }
    private func key(_ suffix: String, _ part: String) -> String { "multiteam.event.\(suffix).\(part)" }

    var title: String {
        switch kind {
        case let .nowOn(ref, _, _):
            return key("nowOn", "title").localized(with: account(ref.profileId), name(ref.orgId))
        case let .adminMove(_, from, to):
            return key("adminMove", "title").localized(with: name(from), name(to))
        case let .groupMove(from, to, moves, notMoved, unchecked):
            let count = moves.count + notMoved.count + unchecked.count
            if let to {
                return key("groupMove", "title").localized(with: count, name(from), name(to))
            }
            return key("groupMove.removed", "title").localized(with: count, name(from))
        case let .teamRemoved(_, org):
            return key("teamRemoved", "title").localized(with: name(org))
        case let .teamChanged(_, from, to):
            return key("teamChanged", "title").localized(with: name(from), name(to))
        case let .teamAdded(_, org):
            return key("teamAdded", "title").localized(with: name(org))
        case let .teamRejoined(_, org):
            return key("teamRejoined", "title").localized(with: name(org))
        case let .seatChange(ref, _, _, inferred):
            return key(inferred ? "seatChange.inferred" : "seatChange", "title").localized(with: name(ref.orgId))
        case let .earlyReset(ref, window, _, _):
            return key("earlyReset", "title").localized(with: name(ref.orgId), windowName(window))
        case let .loginLost(profileId, _):
            return key("loginLost", "title").localized(with: account(profileId))
        case let .loginRestored(profileId):
            return key("loginRestored", "title").localized(with: account(profileId))
        case let .oldTeamDeleted(_, org, _):
            return key("oldTeamDeleted", "title").localized(with: name(org))
        }
    }

    var body: String {
        switch kind {
        case let .nowOn(ref, _, _):
            return key("nowOn", "body").localized(with: account(ref.profileId), name(ref.orgId))
        case let .adminMove(profileId, from, to):
            return key("adminMove", "body").localized(with: account(profileId), name(from), name(to))
        case let .groupMove(_, to, moves, notMoved, unchecked):
            var parts: [String] = []
            let other = moves.filter { $0.value != to }
                .map { (account($0.key), $0.value.map(name) ?? "-") }
                .sorted { $0.0 < $1.0 }
                .map { "\($0.0) → \($0.1)" }
            if !other.isEmpty {
                parts.append(key("groupMove", "body").localized(with: other.joined(separator: ", ")))
            }
            if !notMoved.isEmpty {
                parts.append(key("groupMove", "notMoved").localized(with: notMoved.map(account).sorted().joined(separator: ", ")))
            }
            if !unchecked.isEmpty {
                parts.append(key("groupMove", "unchecked").localized(with: unchecked.map(account).sorted().joined(separator: ", ")))
            }
            return parts.joined(separator: "\n")
        case let .teamRemoved(profileId, org):
            return key("teamRemoved", "body").localized(with: account(profileId), name(org))
        case let .teamChanged(profileId, from, to):
            return key("teamChanged", "body").localized(with: account(profileId), name(from), name(to))
        case let .teamAdded(profileId, org):
            return key("teamAdded", "body").localized(with: account(profileId), name(org))
        case let .teamRejoined(profileId, org):
            return key("teamRejoined", "body").localized(with: account(profileId), name(org))
        case let .seatChange(ref, _, _, _):
            return key("seatChange", "body").localized(with: account(ref.profileId), name(ref.orgId))
        case let .earlyReset(ref, window, fromPercent, toPercent):
            return key("earlyReset", "body").localized(
                with: account(ref.profileId), name(ref.orgId), windowName(window), fromPercent, toPercent)
        case let .loginLost(profileId, reason):
            return key("loginLost", "body").localized(with: account(profileId), reason)
        case let .loginRestored(profileId):
            return key("loginRestored", "body").localized(with: account(profileId))
        case let .oldTeamDeleted(profileId, org, _):
            return key("oldTeamDeleted", "body").localized(with: name(org), account(profileId))
        }
    }

    var notifies: Bool {
        switch kind {
        case let .nowOn(_, _, manual): return !manual
        case .teamAdded, .teamRejoined, .loginRestored, .oldTeamDeleted: return false
        default: return true
        }
    }
}

/// Global tracking state, UserDefaults key "multiTeam.globalState".
struct TeamTrackingGlobalState: Codable, Equatable {
    var current: PairRef?
    var manualPickAt: Date?
    var lastRoundAt: Date?
    var lastSwitchNotificationAt: Date?
    var events: [TeamEvent]           // newest first, capped at 50

    static let empty = TeamTrackingGlobalState(
        current: nil, manualPickAt: nil, lastRoundAt: nil, lastSwitchNotificationAt: nil, events: [])

    static let maxEvents = 50

    mutating func appendEvent(_ event: TeamEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents { events.removeLast(events.count - Self.maxEvents) }
    }
}
