import Foundation

enum PollOutcome: Equatable {
    case success
    case rateLimited(retryAfter: TimeInterval?)
    case failed
}

struct PollPolicy: Equatable {
    var roundInterval: TimeInterval = 300
    var firstRoundDelay: TimeInterval = 15
    var listInterval: TimeInterval = 900
    var listStartSpread: TimeInterval = 10
    var forcedListDebounce: TimeInterval = 60
    var backoffBase: TimeInterval = 60
    var backoffCap: TimeInterval = 900
    var retryAfterCap: TimeInterval = 3600
    var jitter = 0.2
    var maxConcurrent = 4
    var maxPerAccount = 1
    var tick: TimeInterval = 15
    static let `default` = PollPolicy()
}

/// Pure value-type scheduler: says when rounds and org lists are due. No clock, no I/O.
struct TeamPollScheduler {
    private struct Account {
        var hasOrgList: Bool
        var nextList: Date?
        var lastForced: Date?
        var rateLimitCount = 0
        var backoffUntil: Date?
    }

    let policy: PollPolicy
    private let random: () -> Double
    private var nextRound: Date?
    private var accounts: [UUID: Account] = [:]

    init(policy: PollPolicy = .default, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.policy = policy
        self.random = random
    }

    var registeredAccounts: Set<UUID> { Set(accounts.keys) }

    mutating func start(now: Date) {
        nextRound = now.addingTimeInterval(policy.firstRoundDelay)
    }

    mutating func register(accountId: UUID, hasOrgList: Bool, now: Date) {
        guard accounts[accountId] == nil else { return }
        let due = hasOrgList ? now.addingTimeInterval(random() * policy.listStartSpread) : nil
        accounts[accountId] = Account(hasOrgList: hasOrgList, nextList: due)
    }

    mutating func unregister(accountId: UUID) {
        accounts[accountId] = nil
    }

    func isRoundDue(now: Date) -> Bool {
        guard let nextRound else { return false }
        return now >= nextRound
    }

    mutating func roundStarted(now: Date) {
        nextRound = now.addingTimeInterval(policy.roundInterval)
    }

    func dueLists(now: Date) -> [UUID] {
        accounts
            .compactMap { id, a -> (UUID, Date)? in
                guard let due = a.nextList, due <= now, !isBackingOff(id, now: now) else { return nil }
                return (id, due)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.uuidString < $1.0.uuidString }
            .map { $0.0 }
    }

    mutating func listFinished(accountId: UUID, outcome: PollOutcome, now: Date) {
        guard accounts[accountId] != nil else { return }
        let next = now.addingTimeInterval(policy.listInterval)
        if accounts[accountId]?.hasOrgList == true { accounts[accountId]?.nextList = next }
        record(accountId: accountId, outcome: outcome, now: now)
    }

    @discardableResult
    mutating func forceList(accountId: UUID, now: Date, bypassDebounce: Bool = false) -> Bool {
        guard let a = accounts[accountId], a.hasOrgList, !isBackingOff(accountId, now: now) else { return false }
        if !bypassDebounce, let last = a.lastForced, now.timeIntervalSince(last) < policy.forcedListDebounce {
            return false
        }
        accounts[accountId]?.nextList = now
        accounts[accountId]?.lastForced = now
        return true
    }

    mutating func record(accountId: UUID, outcome: PollOutcome, now: Date) {
        guard var a = accounts[accountId] else { return }
        switch outcome {
        case .success:
            a.rateLimitCount = 0
            a.backoffUntil = nil
        case .failed:
            break
        case .rateLimited(let retryAfter):
            a.rateLimitCount += 1
            let nominal = min(policy.backoffBase * pow(2, Double(min(a.rateLimitCount - 1, 30))), policy.backoffCap)
            var delay = nominal * (1 - policy.jitter + 2 * policy.jitter * random())
            if let retryAfter, retryAfter > delay {
                delay = min(retryAfter, policy.retryAfterCap)
            }
            a.backoffUntil = now.addingTimeInterval(delay)
        }
        accounts[accountId] = a
    }

    func isBackingOff(_ accountId: UUID, now: Date) -> Bool {
        guard let until = accounts[accountId]?.backoffUntil else { return false }
        return now < until
    }

    func backoffUntil(_ accountId: UUID) -> Date? {
        accounts[accountId]?.backoffUntil
    }
}
