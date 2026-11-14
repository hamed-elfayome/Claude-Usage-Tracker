<!-- source: .lean/plans/multi-team-packets.md lines 321-393 -->
### MT-5 — Poll scheduler (rounds, org lists, forced lists, 429 backoff) and bounded task runner

Size: M
Risk: high
Importance: normal

**Goal:** Two small, self-contained pieces the tracker (MT-6) drives: a pure value-type scheduler that says
when the next probe round and each account's org list are due, debounces forced lists and keeps per-account
429 backoff; and a runner that executes async work with at most 4 in flight and at most 1 per account. They
know nothing about orgs, profiles or the API. Spec `docs/specs/multi-team-tracking.md` §7.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/TeamPollScheduler.swift`
- NEW `Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift`
- NEW `Claude UsageTests/TeamPollSchedulerTests.swift`, `Claude UsageTests/BoundedTaskRunnerTests.swift`

**Steps**
1. Types:
   ```swift
   enum PollOutcome: Equatable { case success; case rateLimited(retryAfter: TimeInterval?); case failed }
   struct PollPolicy: Equatable { var roundInterval: TimeInterval = 300; var firstRoundDelay: TimeInterval = 15
     var listInterval: TimeInterval = 900; var listStartSpread: TimeInterval = 10; var forcedListDebounce: TimeInterval = 60
     var backoffBase: TimeInterval = 60; var backoffCap: TimeInterval = 900; var retryAfterCap: TimeInterval = 3600
     var jitter = 0.2; var maxConcurrent = 4; var maxPerAccount = 1; var tick: TimeInterval = 15; static let `default` = PollPolicy() }
   ```
2. `struct TeamPollScheduler` (value type; `random: () -> Double` injected in `init(policy:random:)`; every
   method takes `now: Date`; no `Date()` inside):
   - `mutating func start(now:)` → first round due at `now + firstRoundDelay`.
   - `mutating func register(accountId: UUID, hasOrgList: Bool, now:)` — idempotent; list due at
     `now + random()·listStartSpread`; accounts without org list get no list job.
   - `mutating func unregister(accountId:)`; `var registeredAccounts: Set<UUID>`.
   - `func isRoundDue(now:) -> Bool`; `mutating func roundStarted(now:)` → next round `now + roundInterval`.
   - `func dueLists(now:) -> [UUID]` ordered by due time, skipping accounts in backoff.
   - `mutating func listFinished(accountId:, outcome:, now:)` → next list `now + listInterval`, then `record`.
   - `mutating func forceList(accountId:, now:, bypassDebounce: Bool = false) -> Bool` — makes the list due now
     unless forced within `forcedListDebounce` (and not bypassed) or the account is backing off; returns whether it did.
   - `mutating func record(accountId:, outcome:, now:)` — backoff: k = consecutive `rateLimited`; delay =
     min(base·2^(k−1), cap) · (1 − jitter + 2·jitter·random()); if `retryAfter` is larger use
     min(retryAfter, retryAfterCap). `success` → k = 0, backoff cleared. `failed` → unchanged.
   - `func isBackingOff(_:, now:) -> Bool`, `func backoffUntil(_:) -> Date?`.
3. `BoundedTaskRunner`:
   ```swift
   enum BoundedTaskRunner {
     static func run<Item, Result>(_ items: [Item], key: (Item) -> UUID, maxConcurrent: Int, maxPerKey: Int,
       timeout: TimeInterval? = nil, body: @escaping @Sendable (Item) async -> Result) async -> [(Item, Result?)] }
   ```
   Uses a `TaskGroup`; never more than `maxConcurrent` bodies running, never more than `maxPerKey` for one
   key; returns every item in input order with `nil` result when the overall `timeout` elapsed before it
   finished (remaining child tasks cancelled). Respect cancellation of the calling task.
4. Tests, then Validate.

**Acceptance criteria**
1. `start(now: t)` → `isRoundDue(t+14) == false`, `isRoundDue(t+15) == true`; after `roundStarted(t+15)` next due `t+315`.
2. `register` with random 0.5 → list due at +5 s; after `listFinished(.success)` at t → due again at t+900.
3. Account without org list → never in `dueLists`.
4. 429 outcomes 1…6 with random 0.5 → backoff 60, 120, 240, 480, 900, 900 s.
5. random 0 / random 0.999 → delay within [0.8, 1.2] × nominal.
6. `rateLimited(retryAfter: 1800)` at k=1 → 1800 s; `retryAfter: 7200` → 3600 s.
7. Backing-off account → not in `dueLists`, `forceList` returns false; other accounts unaffected.
8. `success` after backoff → `isBackingOff == false`; next 429 starts at 60 s again.
9. `forceList` twice within 60 s → true, false; with `bypassDebounce: true` → true; after 60 s → true.
10. `unregister` → its list never due; `record` for an unknown account → no crash.
11. Runner: 10 items over 10 keys, bodies sleep 50 ms → observed max concurrency 4.
12. Runner: 3 items of one key → never 2 at once.
13. Runner: `timeout` 0.1 s with a body sleeping 2 s → that item returns nil, call returns in < 1 s.
14. Full suite passes.

**Tests:** fixed `random` closures, explicit `Date` values; runner tests count concurrency with an actor
counter. Edge cases: register same account twice (due time kept); `listFinished` for an unregistered account
(not re-added); empty item list.

**Validate:** `.lean/tasks/MT-5/validate/run.sh` (no full Xcode on this machine: compiles the MT-5 sources and tests with an XCTest shim; must print "Executed 17 tests, 0 failures") `git diff --check`
Full-Xcode machines additionally run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` (not runnable where xcode-select points at CommandLineTools).
