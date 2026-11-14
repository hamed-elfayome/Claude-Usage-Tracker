### MT-4 — Multi-org poll scheduler with concurrency cap and 429 backoff

Size: M
Risk: high
Importance: normal

**Goal:** A self-contained actor that decides which poll jobs are due, runs at most 4 at once and at
most 1 per account, spreads start-up, and keeps per-account exponential 429 backoff. It knows nothing
about orgs' meaning, Profiles or the API: it schedules opaque jobs. Spec: `docs/specs/multi-team-tracking.md` §6.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/MultiOrgPollScheduler.swift`
- NEW `Claude UsageTests/MultiOrgPollSchedulerTests.swift`

**Steps**
1. Types:
   ```swift
   struct PollJob: Hashable { enum Kind: Hashable { case orgList; case usage(orgId: String) }; let accountId: UUID; let kind: Kind }
   enum PollOutcome: Equatable { case success; case rateLimited(retryAfter: TimeInterval?); case failed }
   struct PollPolicy { var idleInterval: TimeInterval = 300; var orgListInterval: TimeInterval = 900
     var maxConcurrent = 4; var maxPerAccount = 1; var backoffBase: TimeInterval = 60; var backoffCap: TimeInterval = 900
     var retryAfterCap: TimeInterval = 3600; var jitter = 0.2; var forcedListDebounce: TimeInterval = 60
     var tick: TimeInterval = 15; static let `default` = PollPolicy() }
   ```
2. `actor MultiOrgPollScheduler` with `init(policy: PollPolicy = .default, clock: @escaping @Sendable () -> Date = { Date() }, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) })`.
3. API (all `async` actor methods):
   - `register(_ job: PollJob, interval: TimeInterval)` — idempotent; first due time = now + random·interval
     (org list jobs: now + random·10 s); re-register with a new interval keeps the due time if earlier.
   - `unregister(_ job:)`, `unregisterAll(accountId:)`.
   - `forceSoon(_ job:) -> Bool` — makes the job due now unless it was forced within `forcedListDebounce`; returns whether it was forced.
   - `dueJobs(now: Date? = nil) -> [PollJob]` — due jobs ordered by due time, skipping accounts in backoff,
     respecting `maxConcurrent − inFlight` and `maxPerAccount`; does NOT mark them started.
   - `markStarted(_:)`, `markFinished(_:outcome:)` — finished sets next due = now + interval and applies the outcome.
   - `record(accountId:outcome:)` — applies an outcome without a job (used by the menu bar loop).
   - `isBackingOff(_ accountId:) -> Bool`, `backoffUntil(_:) -> Date?`.
   - `run(execute: @escaping @Sendable (PollJob) async -> PollOutcome)` — loop until the Task is cancelled:
     take `dueJobs`, mark started, run each in a child task (TaskGroup or detached children), mark finished;
     sleep `policy.tick` between passes (`Task.sleep`). Must not run two instances of the same job.
4. Backoff per account: k = consecutive `rateLimited` outcomes; delay = min(base·2^(k−1), cap) ·
   (1 − jitter + 2·jitter·random); if `retryAfter` is larger use min(retryAfter, retryAfterCap).
   `success` resets k and clears backoff; `failed` leaves backoff unchanged.
5. No `Date()` calls outside the injected clock. No singletons. Tests, then Validate.

**Acceptance criteria**
1. Registered usage job with random=0 → due at registration time; after `markFinished(.success)` due again exactly 300 s later.
2. Random=0.5 → first due at +150 s (usage) and +5 s (org list).
3. 10 due jobs over 10 accounts → `dueJobs` returns 4; after marking 4 started, returns 0 until one finishes.
4. 3 due jobs of one account → `dueJobs` returns 1.
5. 429 outcomes 1..6 with random=0.5 (jitter neutral) → backoff 60, 120, 240, 480, 900, 900 s.
6. Random=0 / random≈1 → delay within [0.8, 1.2] × nominal.
7. `rateLimited(retryAfter: 1800)` at k=1 → backoff 1800 s; `retryAfter: 7200` → 3600 s.
8. While backing off, the account's jobs are not returned; other accounts' jobs are.
9. `success` after backoff → `isBackingOff == false`, next 429 starts at 60 s again.
10. `forceSoon` twice within 60 s → first true, second false; after 60 s true again.
11. `unregisterAll(accountId:)` → none of its jobs returned.
12. `run` with an execute closure that sleeps → observed max concurrency ≤ 4 and per-account ≤ 1 (test with a short `tick`, cancel after a few passes).
13. Full suite passes.

**Tests:** inject a mutable test clock (class box) and fixed random. Edge cases: register same job twice,
unregister unknown job, `markFinished` for a job that was unregistered meanwhile (no crash, not re-added),
`record(accountId:)` for an account with no jobs.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
