# Multi-team tracking — build plan

Spec: `docs/specs/multi-team-tracking.md` (read §3–§8 before any packet). Requirements: `docs/specs/multi-team-requirements.md`.
Branch: `feat/multi-team-tracking`. Per-task packets: `.lean/plans/MT-<n>.md` (same text as below).

Order: MT-1 → MT-2 → MT-5 → MT-6 → MT-8 is the critical path. MT-3 and MT-4 start at once (own files only);
MT-7 starts after MT-1 (UI reads only the MT-1 model). Only MT-1 and MT-7 edit `Localizable.strings`.
No packet edits `project.pbxproj` (file-system synchronized groups).

### MT-1 — Org tracking data model, profile field, migration, history keyed by pair

Size: M
Risk: high
Importance: high

**Goal:** Add the per-(account, org) data model, store it on `Profile`, migrate existing profiles
without data loss (R10), and let `UsageHistoryService` read/write history by a string key so each
pair has its own history while the legacy per-profile file stays attached to the first org.
Spec: `docs/specs/multi-team-tracking.md` §3 (types are the contract; copy them exactly).

**Files**
- NEW `Claude Usage/Shared/MultiTeam/OrgTrackingModels.swift`
- NEW `Claude Usage/Shared/MultiTeam/OrgTrackingMigration.swift`
- `Claude Usage/Shared/Models/Profile.swift` (stored property, `init`, `CodingKeys` :149-167, `init(from:)` :169-205, `encode(to:)` :207+)
- `Claude Usage/Shared/Services/ProfileManager.swift` (`loadProfiles()` :30-58; add one method)
- `Claude Usage/Shared/Services/UsageHistoryService.swift` (whole file, 411 lines: init :46, dir :58-69, file URL :71-72, cache :38, record* :182-300, getters :306+)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (every language folder)
- NEW tests: `Claude UsageTests/OrgTrackingModelsTests.swift`, `Claude UsageTests/OrgTrackingMigrationTests.swift`, `Claude UsageTests/UsageHistoryKeyTests.swift`

New `.swift` files join the targets automatically (file-system synchronized groups). Do not edit `project.pbxproj`.

**Steps**
1. In `OrgTrackingModels.swift` define exactly the §3 types: `UsageWindow`, `SeatFingerprint`,
   `TrackedOrgStatus`, `PendingChange`, `TrackedOrg` (with `static let unknownOrgId = "unknown-org"`),
   `AuthState`, `OrgEvent` (+ nested `Kind`), `OrgTrackingState`. All `Codable, Equatable`
   (synthesized). Add `OrgTrackingState.empty` (no orgs, `authState: .ok`, flags false, no events) and
   `mutating func appendEvent(_:)` that inserts at index 0 and caps `recentEvents` at 50.
2. `OrgEvent`: `init(kind:orgNames:date:id:)` with `id = UUID()` and `date = Date()` defaults.
   `title`/`body` via localized keys `multiteam.event.<case>.title|body` with `%@` placeholders for
   org names (`orgNames[id] ?? String(id.prefix(8))`) and `%.0f` for percents. Titles (English):
   ownerSwitch "Now using team %@"; adminMove "Moved by admin: %@ → %@"; orgChanged
   "Team changed: %@ → %@"; orgRemoved "Removed from team %@"; orgAdded "Added to team %@";
   orgRejoined "Back in team %@"; seatChange "Seat changed in %@" (inferred: "Limit size changed in %@");
   earlyReset "Early reset: %@ %@ limit" (team, "5-hour"/"weekly"); loginLost "Log in again";
   loginRestored "Login restored". `notifies` is false for orgAdded, orgRejoined, loginRestored.
   Also add key `multiteam.login_again` = "Log in again" (used by later packets).
3. Add every new key to `en.lproj/Localizable.strings` AND, with the same English value, to every
   other `*.lproj/Localizable.strings` (NSLocalizedString does not fall back to English).
4. `Profile`: add `var orgTracking: OrgTrackingState?` (default nil in `init`), a `CodingKeys` case,
   decode with `(try? c.decodeIfPresent(OrgTrackingState.self, forKey: .orgTracking)) ?? nil`, and
   encode with `encodeIfPresent`. It is NOT a secret (no Keychain handling).
5. `OrgTrackingMigration.migrate(_ profile: Profile, credentialOrgId: String?, now: Date = Date()) -> Profile`:
   - return unchanged when `profile.provider != .anthropic` or `orgTracking != nil`;
   - org id = `organizationId` ?? `credentialOrgId` ?? `organizationUuid` parsed from
     `oauthAccountJSON` (JSONSerialization) ?? `TrackedOrg.unknownOrgId`;
   - name = `oauthAccountJSON.organizationName` when its `organizationUuid` equals the org id, else "Team";
   - one `TrackedOrg(status: .active, historyKey: profile.id.uuidString, lastUsage: profile.claudeUsage,
     lastSampleAt: profile.claudeUsage?.lastUpdated, firstSeenAt: now, missingFromListCount: 0,
     consecutiveUsageAuthFailures: 0, baselineStartedAt: now)`;
   - state: `activeOrgId` = that id, `legacyHistoryKeyAssigned = true`, `authState = .ok`.
   Also add `static func pairHistoryKey(profileId: UUID, orgId: String) -> String` returning
   `"\(profileId.uuidString)_\(orgId)"`.
6. `ProfileManager.loadProfiles()`: after loading, map profiles through
   `OrgTrackingMigration.migrate(_, credentialOrgId: nil)`; if any changed, save once with
   `profileStore.saveProfiles`. Add `func updateOrgTracking(_ state: OrgTrackingState, for profileId: UUID)`
   that updates `profiles`, `activeProfile` when it matches, and saves (follow `saveClaudeUsage` :434).
7. `UsageHistoryService`: switch internal storage to `String` keys (cache `[String: UsageHistoryData]`,
   file `usageHistory_<key>.json`, defaults keys `lastSessionRecordTime_<key>`/`lastWeeklyRecordTime_<key>`).
   Add public `forKey:` variants of `loadHistory`, `saveHistory`, `recordSessionReset`,
   `recordWeeklyReset`, `recordSessionPeriodic`, `recordWeeklyPeriodic`, `getSessionSnapshots`,
   `getWeeklySnapshots`. Every existing UUID method keeps its signature and calls the `forKey:`
   variant with `profileId.uuidString` (file names unchanged). Add an internal
   `init(defaults: UserDefaults, directory: URL)` for tests; `shared` keeps today's directory.
8. Write the tests below. Run Validate.

**Acceptance criteria**
1. Legacy profile JSON without `orgTracking` → decodes, `orgTracking == nil`, other fields unchanged.
2. Profile JSON whose `orgTracking` is a corrupt object → decodes, `orgTracking == nil`, profile kept.
3. `OrgTrackingState` with every `OrgEvent.Kind` case → JSON round trip equal.
4. `appendEvent` 51 times → 50 events, newest first.
5. migrate(anthropic, organizationId "A", claudeUsage U) → one org "A", `.active`, historyKey = profile UUID string, lastUsage U.
6. migrate(organizationId nil, credentialOrgId "B") → org "B".
7. migrate(organizationId nil, credentialOrgId nil, oauthAccountJSON with organizationUuid "C", organizationName "Acme") → org "C", name "Acme".
8. migrate(nothing known) → org `unknown-org`.
9. migrate on a profile already migrated → identical profile; migrate on a `.codex` profile → unchanged.
10. `recordSessionPeriodic(for: uuid, …)` writes `usageHistory_<UUID>.json` in the injected directory (same name as before).
11. `recordSessionPeriodic(forKey: "U_orgB", …)` writes `usageHistory_U_orgB.json`; the UUID file is untouched.
12. Record-time throttling is per key: two keys can record in the same minute.
13. `OrgEvent(kind: .adminMove(from:"a",to:"b"), orgNames:["a":"A","b":"B"]).title` == "Moved by admin: A → B"; `.orgAdded` → `notifies == false`.
14. Full existing test suite passes.

**Tests** (XCTest, new files above; use a temp directory + `UserDefaults(suiteName:)` removed in tearDown)
- Edge cases: empty `oauthAccountJSON`, malformed `oauthAccountJSON`, profile with `claudeUsage == nil`,
  key with characters `-` and `_`, unknown event org id → prefix fallback in title.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

### MT-2 — Pure event classifier and credential-org parser

Size: M
Risk: normal
Importance: high
After: MT-1

**Goal:** Implement the §5 event state machine of `docs/specs/multi-team-tracking.md` as a pure,
fully tested function, plus pure parsing of the Claude Code login's org and seat. No network, no
Keychain, no singletons. Read spec §4 and §5 before coding; the rules and thresholds there are the
decisions — do not change them.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/OrgEventClassifier.swift`
- NEW `Claude Usage/Shared/MultiTeam/CredentialOrgParser.swift`
- NEW `Claude UsageTests/Fixtures/MultiTeamFixtures.swift` (Swift string literals + builders)
- NEW `Claude UsageTests/OrgEventClassifierTests.swift`, `Claude UsageTests/CredentialOrgParserTests.swift`
- Read only: `Claude Usage/Shared/MultiTeam/OrgTrackingModels.swift` (from MT-1), `Shared/Models/ClaudeUsage.swift`,
  `Shared/Models/UsageHistory.swift:323-335` (`ResetDetection.tolerance`, reuse it).

**Steps**
1. `CredentialOrgParser` (enum, static funcs):
   - `orgId(fromCredentialsJSON:) -> String?`: root `organizationUuid`, else `claudeAiOauth.organizationUuid`; empty → nil.
   - `orgId(fromOAuthAccountJSON:) -> String?` and `orgName(fromOAuthAccountJSON:) -> String?`.
   - `seat(fromCredentialsJSON:) -> SeatFingerprint?`: present non-empty `claudeAiOauth.rateLimitTier`,
     `claudeAiOauth.subscriptionType` joined by `|`, source `.credentials`; none → nil.
   - `seat(rateLimitTier:ravenType:billingType:) -> SeatFingerprint?` (source `.orgList`, same join order).
2. In the classifier file define `OrgListEntry { orgId, name, seat: SeatFingerprint?, canChat: Bool }`,
   `AccountObservation` (fields and defaults exactly as spec §5, plus `credentialChanged: Bool = false`),
   `ResetSnapshot { orgId, window, previous: ClaudeUsage }`, and
   `ClassificationResult { state, events, acceptedSamples: [String: ClaudeUsage], resetSnapshots: [ResetSnapshot] }`.
3. `enum OrgEventClassifier { static func apply(_ obs: AccountObservation, to state: OrgTrackingState, profileId: UUID) -> ClassificationResult }`.
   Use `obs.now` for every time decision (never `Date()`). Order inside: unknown-org rename → L → M → W → S → R,
   with precedence L > M > W > S > R as spec §5. Implement each rule as a private static func.
4. Details the spec leaves to code:
   - Ignore list entries with `canChat == false`.
   - New org history key: if `!legacyHistoryKeyAssigned` → `profileId.uuidString` and set the flag;
     else `OrgTrackingMigration.pairHistoryKey(profileId:orgId:)`.
   - Unknown-org rename: a pair with `unknownOrgId` and a known credential org (or the only chat org
     in a list) → set its `orgId` in place unless that org is already tracked; then mark the unknown pair `.removed`.
   - `missingFromListCount` increments only when `obs.now − state.lastOrgListAt ≥ 60 s` (or no previous list);
     reset to 0 when listed. Set `lastOrgListAt = obs.now` after a successful list.
   - Usage membership failure (`usageMembershipFailures`) sets `lastMembershipFailureAt = now` and
     increments `consecutiveUsageAuthFailures`; any accepted sample resets it to 0.
   - L3 uses `consecutiveUsageAuthFailures ≥ 2` on the credential org pair with `oauthUnauthorized`.
   - While `authState` is `needsLogin`: samples for that account are still accepted only if
     `credentialChanged` or any sample arrived (that is the restore signal → `loginRestored`).
   - Window presence: session = `hasSessionLimit` in both samples; weekly = `hasWeeklyLimit` in both.
     S2 per-model windows: `opusWeeklyPercentage`, `sonnetWeeklyPercentage` when previous ≥ 5.
   - When the S2 candidate test matches a sample, R is not evaluated for that pair in that run
     (S > R), so a proportional drop becomes `pending(.seatInferred)`, never `pending(.earlyReset)`.
   - Confirmed early reset → event + a `ResetSnapshot` with the baseline usage. Natural reset → `ResetSnapshot` only.
   - Every accepted sample updates `lastUsage`, `lastSampleAt`; identity events restart the baseline
     (`baselineStartedAt = now`, `pending = nil`).
   - Events get `orgNames` from tracked orgs + list entries. Append via `appendEvent`.
   - Active org selection fallback = first live `canChat` org in list order.
5. Fixtures (`MultiTeamFixtures`): org list JSON strings `orgsAB`, `orgsB`, `orgsABC`, `orgsAStandard`,
   `orgsAPremium` (`rate_limit_tier` differs), `orgsAPIOnly`; `usageJSON(session:weekly:sessionReset:weeklyReset:)`
   builder producing `/usage` bodies (`five_hour`, `seven_day`, `seven_day_opus`, ISO8601 with fractional
   seconds) and `usageNoFiveHour`; credentials JSON `credentialsOrgA/B/NoOrg`; `oauthAccountOrgA/B`.
   Decode usage bodies with `ClaudeAPIService().parseUsageResponse(_:)` in tests so samples are real parser output.
6. Write the tests. Run Validate.

**Acceptance criteria**
1. Credential org A→B, list has A and B → one `ownerSwitch(A→B)`; B `.active`, A `.idle`; no reset event.
2. Credential org A→B, `hasOrgListAccess == false` → `orgChanged(A→B)`; A `.readOnly`.
3. List [A,B] then [B] (≥ 60 s later) then [B] (≥ 60 s later) with A active → `adminMove(A→B)` on the confirming list; A `.removed`, history key kept.
4. List [B] once + A had a 404 within 10 min → `adminMove(A→B)` immediately.
5. List [A] → [] or failed list (`orgList == nil`) → no membership change.
6. Org A missing (confirmed) and no new org → `orgRemoved(A)`.
7. Removed A appears again → A `.idle`, `orgRejoined(A)` with `notifies == false`.
8. Same org, seat fingerprint `orgList` "std" → "premium" → `seatChange(inferred: false)`; source change credentials→orgList → no event.
9. No fingerprint; session 40→10 and weekly 20→5 with unchanged reset times, next sample 11/5 → `seatChange(inferred: true)`; next sample 40/20 instead → no event.
10. Session 60 → 5 with reset 3 h away, next sample 6 → `earlyReset(session, 60, 6)` + one `ResetSnapshot`; next sample 61 instead → nothing.
11. Session 60 → 0 when `prev.sessionResetTime ≤ now + 5 min` and reset time moved → natural `ResetSnapshot`, no event.
12. Reset time moved 2 h while not due and no drop → no snapshot, no event.
13. `five_hour` missing in the new sample (parsed as 0 %) → no event for the session window.
14. `ownerSwitch` and a session drop in the same observation → only `ownerSwitch`, pending cleared.
15. `refreshRejected` → `needsLogin`, `loginLost` event; next observation with a sample → `.ok`, `loginRestored`.
16. `orgListAuthFailed` → `needsLogin`; OAuth-only 401 once → still `.ok`; twice → `needsLogin`.
17. Pending early reset older than 30 min → discarded with no event.
18. Pair `unknown-org` + credential org "A" (not tracked) → pair renamed to "A", same historyKey, no event.
19. `CredentialOrgParser` reads root and nested `organizationUuid`, returns nil for garbage JSON.
20. Full suite passes.

**Tests:** one XCTest method per acceptance line 1–19, plus edge cases: list containing only an
API-only org; two orgs added at once with no credential org (newest `firstSeenAt` wins); A→B→C between
two observations (collapses to A→C, R11); weekly-only plan (`hasSessionLimit == false`).

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

### MT-3 — API layer: tier fields, 404/429 mapping with Retry-After, usage-only fetch

Size: S
Risk: normal
Importance: normal

**Goal:** Give the multi-team code the API signals it needs, without changing today's behaviour for
existing callers. Spec: `docs/specs/multi-team-tracking.md` §2 (status mapping row), §4, §6.

**Files**
- `Claude Usage/Shared/Services/ClaudeAPIService+Types.swift` (`AccountInfo` :28-32)
- `Claude Usage/Shared/Services/ClaudeAPIService.swift` (1369 lines; touch only: `fetchUsageData(sessionKey:organizationId:)` area :513, `fetchUsageData(oauthAccessToken:)` :545-570, `performRequest` status switch :807-866)
- NEW `Claude Usage/Shared/MultiTeam/AppError+MultiTeam.swift`
- NEW `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`

**Steps**
1. `AccountInfo`: add `var rateLimitTier: String? = nil`, `var billingType: String? = nil`,
   `var ravenType: String? = nil` and a `CodingKeys` enum mapping `uuid`, `name`, `capabilities`,
   `rate_limit_tier`, `billing_type`, `raven_type`. Keep `uuid`, `name`, `capabilities` required (as
   today). Existing memberwise calls `AccountInfo(uuid:name:capabilities:)` must still compile
   (`PreferredOrganizationTests`).
2. Extract the status switch of `performRequest` into
   `static func error(forStatus status: Int, data: Data, response: HTTPURLResponse, endpoint: String) -> AppError?`
   (nil for 200). `performRequest` calls it and throws the result. Same messages as today, plus:
   - `404` → `AppError(code: .apiNotFound, …)` (was `.apiGenericError`);
   - `429` → `technicalDetails` gains a line `Retry-After: <seconds>` when the header is present
     (integer seconds; ignore HTTP-date values).
3. `fetchUsageData(oauthAccessToken:)`: map 429 → `.apiRateLimited` with the same `Retry-After` line;
   keep 401/403 → `.apiUnauthorized`, everything else → `.apiGenericError`.
4. Add `func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage`
   next to `fetchUsageData(sessionKey:organizationId:)`: one `performRequest` to
   `/organizations/<id>/usage` then `parseUsageResponse`. No overage/credit/spend calls.
5. `AppError+MultiTeam.swift`: `extension AppError { var retryAfterSeconds: TimeInterval? }` (parse the
   `Retry-After:` line of `technicalDetails`), `var isCloudflareChallenge: Bool { code == .apiServiceUnavailable }`,
   `var isMembershipFailure: Bool { code == .apiUnauthorized || code == .apiNotFound }`,
   `var isRateLimited: Bool { code == .apiRateLimited }`.
6. Before changing 404, `grep -rn "apiGenericError" "Claude Usage"` and confirm no caller depends on a
   404 being generic; note the result in the walkthrough.
7. Tests, then Validate.

**Acceptance criteria**
1. Decoding `[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":"b","raven_type":"team"}]` → fields set.
2. Decoding the same without the three fields → nil fields, no error.
3. `error(forStatus: 404, …)` → code `.apiNotFound`.
4. `error(forStatus: 429, …)` with header `Retry-After: 120` → `.apiRateLimited`, `retryAfterSeconds == 120`.
5. 429 without the header → `retryAfterSeconds == nil`.
6. 403 with body containing "Just a moment" → `.apiServiceUnavailable`, `isCloudflareChallenge == true`, `isMembershipFailure == false`.
7. 401 plain → `.apiUnauthorized`, `isMembershipFailure == true`.
8. 200 → nil.
9. `fetchUsageOnly` issues exactly one request (verified by reading the code path; it calls `performRequest` once).
10. Full suite passes (incl. `PreferredOrganizationTests`, `ClaudeAPIServiceParsingTests`).

**Tests:** build `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)` objects directly — no
network. Edge cases: `Retry-After: abc`, `Retry-After: 0`, Cloudflare header `cf-mitigated` with 401,
500 still → `.apiServerError`.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

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

---

### MT-5 — Multi-team coordinator with injected adapters

Size: M
Risk: high
Importance: high
After: MT-2, MT-3, MT-4

**Goal:** One `@MainActor` coordinator that owns, for every anthropic profile: org-list refresh,
idle-pair polling through the scheduler, credential-org reading, classification, persistence of
`orgTracking`, the `claudeUsage`/`organizationId` invariants, per-pair history and event
notifications. It also exposes the small contract the menu bar loop will call in MT-6. No edits to
MenuBarManager here. Spec: `docs/specs/multi-team-tracking.md` §4, §6, §7, §9.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/MultiTeamCoordinator.swift`
- NEW `Claude Usage/Shared/MultiTeam/MultiTeamAdapters.swift`
- `Claude UsageTests/Fixtures/MultiTeamFixtures.swift` (extend only)
- NEW `Claude UsageTests/MultiTeamCoordinatorTests.swift`
- Read only: `OrgEventClassifier.swift`, `CredentialOrgParser.swift`, `MultiOrgPollScheduler.swift`,
  `AppError+MultiTeam.swift`, `ClaudeCodeSyncService.swift` (:679-725 `readOAuthAccount`/`systemHoldsAccount`,
  :880-930 token helpers, :957 `readKeychainCredentials(serviceName:)`), `AnthropicUsageProvider.swift`.

**Steps**
1. Protocols (in the coordinator file):
   ```swift
   protocol OrgUsageFetching { func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo]
     func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage
     func fetchUsage(oauthAccessToken: String) async throws -> ClaudeUsage }
   protocol CredentialOrgReading { func credentialOrg(for profile: Profile) -> (orgId: String?, seat: SeatFingerprint?)
     func usableAccessToken(for profile: Profile) -> String?        // never refreshes
     func credentialFingerprint(for profile: Profile) -> String? }  // changes when session key or refresh token changes
   @MainActor protocol OrgTrackingStore { var trackedProfiles: [Profile] { get }
     func updateOrgTracking(_ s: OrgTrackingState, for id: UUID); func updateOrganizationId(_ id: String?, for profileId: UUID)
     func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID) }
   protocol PairHistoryRecording { recordSessionPeriodic/recordWeeklyPeriodic/recordSessionReset/recordWeeklyReset (forKey: variants from MT-1) }
   @MainActor protocol OrgEventNotifying { func notify(_ event: OrgEvent, profile: Profile) }
   struct ActivePollTicket { let profileId: UUID; let orgId: String; let credentialOrgAtStart: String?; let startedAt: Date }
   ```
2. Adapters in `MultiTeamAdapters.swift`: `ClaudeAPIOrgFetcher` (wraps `ClaudeAPIService`:
   `fetchAllOrganizations(sessionKey:)`, `fetchUsageOnly`, `fetchUsageData(oauthAccessToken:)`);
   `SystemCredentialOrgReader` (spec §4 order 1–4 via `CredentialOrgParser` + `ClaudeCodeSyncService`;
   60 s cache per profile; `usableAccessToken` = token from the pinned keychain entry or
   `cliCredentialsJSON` only when not expired, never `ensureFreshCredentials`; fingerprint = SHA256 prefix
   of session key + refresh token, never logged); `extension ProfileManager: OrgTrackingStore`
   (`trackedProfiles` = anthropic profiles); `extension UsageHistoryService: PairHistoryRecording`;
   `NoopOrgEventNotifier`.
3. `MultiTeamCoordinator` (`@MainActor final class`, `ObservableObject`), `init(store:fetcher:credentials:scheduler:history:notifier:clock:)`;
   `static let shared` wires the real adapters with `NoopOrgEventNotifier`; `var notifier` is settable (MT-6 swaps it).
4. Public contract:
   - `start()` → `syncJobs()` then one `Task` running `scheduler.run(execute:)`; `stop()` cancels it.
   - `syncJobs()` registers per profile: org-list job when it has a session key (900 s); usage jobs
     (300 s) for every `.idle` pair reachable by session key, and for the `.active` pair when the profile
     is not in `loopProfileIds` and is reachable (session key, or credential org with a usable token);
     900 s for pairs with `consecutiveUsageAuthFailures ≥ 3`; unregisters everything else, deleted profiles,
     and accounts in `needsLogin`.
   - `setLoopProfiles(_ ids: Set<UUID>)` stores `loopProfileIds` and calls `syncJobs()` when it changed.
   - `beginActivePoll(for:) -> ActivePollTicket?` — nil when the account is backing off, or `needsLogin`
     and the credential fingerprint has not changed. Org = session key + `organizationId` ? that org :
     credential org ?? `TrackedOrg.unknownOrgId`.
   - `ingestActive(_:result:isCachedReading:)`, `reportRefreshRejected(profileId:)`, `isBackingOff(_:)`,
     `var onActiveOrgChanged: ((UUID) -> Void)?`.
5. One private `process(profileId:observation:)` used by every path: classify → `updateOrgTracking` →
   if session key and `activeOrgId != organizationId` → `updateOrganizationId` → history: for each
   `resetSnapshot` record the reset (`resetTime` = previous window reset time) and skip that window's
   periodic record; periodic records for every accepted sample → events with `notifies` → `notifier.notify`
   → if `activeOrgId` changed: `saveClaudeUsage(newActive.lastUsage)` when present and call
   `onActiveOrgChanged` → `syncJobs()` if any status changed.
6. Job execution: org list → `fetchOrganizations`, map `AccountInfo` → `OrgListEntry` (seat via
   `CredentialOrgParser.seat(rateLimitTier:ravenType:billingType:)`, `canChat = capabilities.contains("chat")`).
   Usage → `fetchUsageOnly` or OAuth. Before classifying, read the credential org; if it differs from
   `state.lastCredentialOrgId` and the profile has a session key, fetch the list inline first. A usage
   error with `isMembershipFailure` → add to `usageMembershipFailures`, then fetch the list inline when
   `scheduler.forceSoon(orgList job)` returns true. Cloudflare → no observation. Outcome mapping:
   `isRateLimited` → `.rateLimited(retryAfterSeconds)`, success → `.success`, else `.failed`.
   Scheduler-path samples of the active pair also `saveClaudeUsage` (invariant 1).
7. `ingestActive`: cached reading → nothing. Re-read the credential org; if it differs from
   `ticket.credentialOrgAtStart` → drop the sample but still process the credential change. Success →
   observation with `samples[ticket.orgId]` (do not `saveClaudeUsage`; the loop does). Failure →
   rate-limit → `scheduler.record`; membership failure → as step 6; `.apiUnauthorized` on an
   OAuth-only profile → `oauthUnauthorized = true`.
8. Tests with fakes (fake fetcher returning fixtures from `MultiTeamFixtures`, fake credentials,
   in-memory store, recording history and notifier, scheduler with test clock). Then Validate.

**Acceptance criteria**
1. Scenario switch: credentials A→B with list [A,B] → store state active B, `organizationId == "B"`, one notification "Now using team B".
2. Scenario move: usage of A returns 404, inline list [B] → `adminMove(A→B)`, A `.removed`, A not scheduled any more.
3. Scenario seat change: list with `rate_limit_tier` std→premium → one `seatChange` notification.
4. Scenario early reset: two active samples 60 % → 5 % → 6 % with reset 3 h away → one `earlyReset` notification and one session reset in history under A's key.
5. Scenario 429: idle poll returns `.apiRateLimited` with Retry-After 120 → `isBackingOff == true`; `beginActivePoll` returns nil for that profile.
6. Scenario login loss: `reportRefreshRejected` → state `needsLogin`, its jobs unregistered, `beginActivePoll` nil; after the fake fingerprint changes, `beginActivePoll` returns a ticket and a success restores `.ok`.
7. Migration scenario: a legacy profile (migrated by MT-1) with history key = profile UUID records periodic history under that key.
8. Ticket dropped: credential org changes between `beginActivePoll` and `ingestActive` → sample not stored in any pair.
9. Idle pair sample never changes `profile.claudeUsage`; active pair sample from the scheduler does.
10. `orgAdded` / `loginRestored` events → no notification.
11. Full suite passes.

**Tests:** one test per acceptance line 1–10. Edge cases: profile deleted while a job is in flight (no
crash, no store write for it); Cloudflare 403 → no event and no list fetch; credential org unreadable →
active org stays the stored pick; two profiles sharing an org id are independent.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

### MT-6 — Wire the coordinator into the menu bar loop, token refresh and notifications

Size: M
Risk: high
Importance: high
After: MT-5

**Goal:** Make the running app use the coordinator: the existing 30 s loop stays the active-pair poller
but asks the coordinator before fetching and hands every anthropic sample to it; per-pair history and
events replace the old reset checks for anthropic profiles; `invalid_grant` reaches the coordinator;
events become macOS notifications; a dead login shows "Log in again". Codex profiles keep today's path.
Spec: `docs/specs/multi-team-tracking.md` §6, §7, §8.

**Files**
- `Claude Usage/MenuBar/MenuBarManager.swift` (1924 lines; touch only `setup()` :121, `cleanup()` :261,
  `cleanupProfile` :316, `observeProfileChanges` :326, `refreshAllSelectedProfiles` :1007-1160,
  `refreshUsage` :1201-1418)
- `Claude Usage/Shared/Services/Providers/Anthropic/AnthropicUsageProvider.swift` (:49-60)
- `Claude Usage/Shared/Services/NotificationManager.swift` (add an extension at the end)
- NEW `Claude UsageTests/OrgEventNotificationTests.swift`
- Read only: `MultiTeamCoordinator.swift`, `OrgTrackingModels.swift`.

**Steps**
1. `setup()`: `MultiTeamCoordinator.shared.notifier = NotificationManager.shared`;
   `onActiveOrgChanged = { [weak self] _ in self?.refreshUsage() }`; `start()`. `cleanup()`: `stop()`.
2. `refreshAllSelectedProfiles`: before the loop call `setLoopProfiles(Set(selectedProfiles.map(\.id)))`.
   For a profile with `provider == .anthropic`: `guard let ticket = coordinator.beginActivePoll(for: profile)`
   else log and `continue` (cached value stays on screen). After a successful fetch, in the existing
   `MainActor.run`: call `coordinator.ingestActive(ticket, result: .success(newUsage), isCachedReading:)`
   and skip `checkAndRecordSessionReset`, `checkAndRecordWeeklyReset`, `recordSessionPeriodic`,
   `recordWeeklyPeriodic` and the `resetJustRecorded` bookkeeping for that profile; keep
   `saveClaudeUsage`, active-profile `self.usage`, and the statusline cache exactly as today. In `catch`,
   call `ingestActive(ticket, result: .failure(error), isCachedReading: false)`.
   Non-anthropic profiles: unchanged code path.
3. `refreshUsage` (single mode): `setLoopProfiles([profile.id])`; the same ticket / ingest / skip pattern
   for the anthropic case around `fetchUsageForActiveProfile`.
4. After each refresh pass, if the active profile's `orgTracking?.authState` is `.needsLogin`, set
   `hasCredentialError = true` and `lastRefreshError` to an `AppError(code: .apiUnauthorized,
   message: "multiteam.login_again".localized, …)` so the existing banner shows; do not reset it to
   false in the same pass. Otherwise keep today's handling.
5. `cleanupProfile` and the profiles-changed observer: call `MultiTeamCoordinator.shared.syncJobs()`.
6. `AnthropicUsageProvider.fetchUsage(for:)`: pass `onRefreshRejected:` to `ensureFreshCredentials`
   that hops to the main actor and calls `MultiTeamCoordinator.shared.reportRefreshRejected(profileId: profile.id)`.
   No other change to the priority chain.
7. `NotificationManager`: `extension NotificationManager: OrgEventNotifying` with
   `notify(_ event:, profile:)` → skip unless `profile.notificationSettings.enabled` and `event.notifies`;
   build content with a pure `static func orgEventContent(_ event: OrgEvent, profileName: String) -> (identifier: String, title: String, body: String)`
   (identifier `org-event-<event.id>`, title = event title, body = "<profileName>: <event body>") and post
   it the same way `sendAutoSwitchNotification` (:308) does.
8. Tests, then Validate. Then launch-free check: build succeeds and the full suite is green.

**Acceptance criteria**
1. Anthropic profile in multi mode → `beginActivePoll` called before fetch; `ingestActive` called after; no call to `checkAndRecordSessionReset`/`checkAndRecordWeeklyReset`/periodic recorders for it (verified by code reading in the walkthrough).
2. Codex profile → old reset checks and periodic recording still run (unchanged lines).
3. `beginActivePoll` returns nil → no network fetch for that profile in that pass.
4. `orgEventContent` for `adminMove(A→B)` and profile "Work" → identifier `org-event-<uuid>`, title "Moved by admin: A → B", body starting "Work: ".
5. `notify` with `notificationSettings.enabled == false` or `event.notifies == false` → nothing posted (test through an injectable post closure or by checking the early return path in a unit test).
6. `ensureFreshCredentials` in `AnthropicUsageProvider` receives a non-nil `onRefreshRejected`.
7. Active profile `needsLogin` → `hasCredentialError == true` after the pass, banner text "Log in again".
8. Full suite passes, including all pre-existing tests.

**Tests:** `OrgEventNotificationTests` for lines 4–5 and every `OrgEvent.Kind` producing a non-empty
title. Edge cases: event with an org id missing from `orgNames`; profile name with emoji/unicode.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

### MT-7 — Popover "Teams — most room left" list, recent events, history org picker

Size: M
Risk: normal
Importance: normal
After: MT-1

**Goal:** Show every (account, org) pair in one list sorted by headroom (R9), the last team events,
"Log in again" rows (R8), and let the history view pick the org. UI reads only `Profile.orgTracking`
(MT-1 data), so it runs in parallel with MT-2…MT-6. Spec: `docs/specs/multi-team-tracking.md` §8.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/RoomLeftRanking.swift`
- NEW `Claude Usage/MenuBar/TeamsSectionView.swift`
- `Claude Usage/MenuBar/PopoverContentView.swift` (1876 lines; only `PopoverContentView.body`, insert after the `ContextualInsights` block at :262-266)
- `Claude Usage/Views/Settings/Profile/UsageHistoryView.swift` (`loadHistory` :176-183 and the reset/export calls :186+)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (every language folder; MT-1 already added event keys — add only UI keys)
- NEW `Claude UsageTests/RoomLeftRankingTests.swift`

Do not touch `MenuBarManager.swift`, `NotificationManager.swift` or `AnthropicUsageProvider.swift` (MT-6 owns them).

**Steps**
1. `RoomLeftRanking` (pure, `now` injected):
   ```swift
   struct RoomLeftRow: Identifiable, Equatable { let id: String; let profileId: UUID; let profileName: String
     let orgId: String; let orgName: String; let isActive: Bool; let sessionLeft: Double?; let weeklyLeft: Double?
     let headroom: Double?; let lastSampleAt: Date?; let state: State
     enum State: Equatable { case ok, stale, needsLogin } }
   static func rows(profiles: [Profile], now: Date) -> [RoomLeftRow]
   static func recentEvents(profiles: [Profile], limit: Int = 5) -> [(profileName: String, event: OrgEvent)]
   ```
   - Only anthropic profiles with `orgTracking`; skip `.removed` pairs; skip pairs with no `lastUsage`
     unless the account is `needsLogin`.
   - `sessionLeft` = 100 − session % when `hasSessionLimit`, 100 when its reset time ≤ now, nil without a 5-hour window.
     `weeklyLeft` likewise from weekly (100 when its reset ≤ now). Clamp to 0…100.
   - `headroom` = min(sessionLeft, weeklyLeft), or weeklyLeft when sessionLeft is nil.
   - `state`: account `needsLogin` → `.needsLogin` (numbers nil); `lastSampleAt` older than 30 min → `.stale`; else `.ok`.
   - Order: `.ok` rows by headroom desc, then weeklyLeft desc, then "profile · org" name asc; then `.stale`
     (same order); then `.needsLogin` by name.
   - `recentEvents`: merge all profiles' `recentEvents`, newest first, limit.
2. `TeamsSectionView(profiles: [Profile])`: header "Teams — most room left"; rows: "<profile> · <org>",
   "5h <n>% left" (omit when nil), "Week <n>% left", a dot for `isActive`, "<n> min ago" for `.stale`,
   "Log in again" text (key `multiteam.login_again` from MT-1) in place of numbers for `.needsLogin`.
   Below: up to 5 events (title + relative time with `RelativeDateTimeFormatter`). Match the popover's
   existing fonts/colors (`UsageRow`, `ContextualInsights` style); width fits the 280 pt popover.
3. `PopoverContentView.body`: after the insights block, show `PopoverDivider()` + `TeamsSectionView(profiles: profileManager.profiles)`
   when ranking returns ≥ 2 rows or any `.needsLogin` row. Collapsible with a chevron, expanded by default,
   state in `@AppStorage("popover.teamsExpanded")`.
4. `UsageHistoryView`: when the active profile has `orgTracking` with more than one pair having a
   `historyKey` (including `.removed`, labelled "(removed)"), show a `Picker` of orgs; default the
   active pair. Load and reset/export through the `forKey:` API with the selected pair's `historyKey`.
   With one pair or no `orgTracking`, behave exactly as today (UUID API).
5. Localize every new string with keys `multiteam.ui.*` in all `.lproj` files (English value everywhere except `en` may be the same).
6. Tests, then Validate.

**Acceptance criteria**
1. Pairs (5h 20 % used, week 50 % used) and (5h 70 % used, week 10 % used) → order: first (headroom 50) before second (headroom 30).
2. Equal headroom → higher weeklyLeft first; still equal → name ascending.
3. Weekly-only plan (no 5-hour window), week 40 % used → `sessionLeft == nil`, headroom 60.
4. Session reset time in the past → sessionLeft 100.
5. Pair sampled 31 min ago → `.stale`, listed after all `.ok` rows.
6. Account `needsLogin` → its rows `.needsLogin`, numbers nil, listed last.
7. `.removed` pair → not listed; codex profile → not listed; profile without `orgTracking` → not listed.
8. `recentEvents` over two profiles → newest first, at most 5.
9. Popover with 1 pair and no `needsLogin` → no Teams section (code path check in walkthrough).
10. `UsageHistoryView` with one pair → still calls the UUID API (unchanged behaviour).
11. A SwiftUI smoke test hosts `TeamsSectionView` in an `NSHostingView` with 3 rows and 2 events and lays it out without crashing.
12. Full suite passes.

**Tests:** `RoomLeftRankingTests` for lines 1–8 and 11 (build `Profile` values in code with `orgTracking`
set; fixed `now`). Edge cases: usage over 100 % (clamped to 0 left), empty profiles array, a pair with
`lastUsage == nil` and account `.ok` (skipped).

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

### MT-8 — User docs and changelog for multi-team tracking

Size: S
Risk: normal
Importance: low
After: MT-6, MT-7

**Goal:** Tell users what the feature does, what each event means, and its limits. Spec:
`docs/specs/multi-team-tracking.md` §5, §8, §12.

**Files**
- `docs/profiles.md` (add a section; keep the existing ones)
- `CHANGELOG.md` (add under the top "Unreleased" heading; create that heading above the newest release if missing)
- `docs/troubleshooting.md` (one entry)

**Steps**
1. `docs/profiles.md`: new section "Several teams per account" — what is tracked (every team the account
   belongs to; the Claude Code login's team is "active"), the event list (Now using team B; Moved by
   admin; Team changed; Removed from team; Seat changed / Limit size changed; Early reset; Log in again)
   with one plain sentence each, the "Teams — most room left" list and its sort order, polling rates
   (active 30 s, other teams 5 min, team list 15 min).
2. Limits subsection: copy the five bullets of spec §12 in plain words (two changes between polls show
   as one; undocumented endpoints; OAuth-only accounts see one team; seat change without a tier field
   may show as early reset; early reset shows one poll late). Include the request to capture a redacted
   `/api/organizations` response per seat type via Settings → Debug network log.
3. `docs/troubleshooting.md`: entry "It says Log in again" — run `claude /login` (or re-sign-in to
   claude.ai in Settings) for that account; the app never logs in for you.
4. `CHANGELOG.md`: one "Added" bullet (multi-team tracking, events, most-room-left list) and one "Changed"
   bullet (a shifted reset time without a usage drop is no longer recorded as a reset; 404 maps to "not found").
5. Plain English, short sentences, no marketing words. Validate.

**Acceptance criteria**
1. `docs/profiles.md` contains a "Several teams per account" section listing all 7 user-visible events.
2. The section lists the three polling intervals and the sort rule.
3. The limits subsection contains the R11 sentence about two changes between polls.
4. `docs/troubleshooting.md` has the "Log in again" entry.
5. `CHANGELOG.md` has the Added and Changed bullets under Unreleased.
6. No code file changed; full suite still passes.

**Tests:** none beyond the suite (docs only). Check links with `grep -n "](" docs/profiles.md` by eye.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

---

## Lanes

| Lane | Tasks | Runs alongside | Saves (min) |
|---|---|---|---|
| A (critical path) | MT-1 → MT-2 → MT-5 → MT-6 → MT-8 | — | 0 |
| B | MT-3 | MT-1, MT-2 | ~20 |
| C | MT-4 | MT-1, MT-2 | ~35 |
| D | MT-7 (after MT-1) | MT-2, MT-5, MT-6 | ~40 |

File ownership while lanes overlap: B = `ClaudeAPIService*.swift`, `AppError+MultiTeam.swift`; C = `MultiOrgPollScheduler.swift`;
D = `PopoverContentView.swift`, `UsageHistoryView.swift`, `TeamsSectionView.swift`, `RoomLeftRanking.swift`, `Localizable.strings`;
A = everything else. No two parallel packets edit the same file.

TASKS: [{"id":"MT-1","size":"M","risk":"high","importance":"high","after":[]},{"id":"MT-2","size":"M","risk":"normal","importance":"high","after":["MT-1"]},{"id":"MT-3","size":"S","risk":"normal","importance":"normal","after":[]},{"id":"MT-4","size":"M","risk":"high","importance":"normal","after":[]},{"id":"MT-5","size":"M","risk":"high","importance":"high","after":["MT-2","MT-3","MT-4"]},{"id":"MT-6","size":"M","risk":"high","importance":"high","after":["MT-5"]},{"id":"MT-7","size":"M","risk":"normal","importance":"normal","after":["MT-1"]},{"id":"MT-8","size":"S","risk":"normal","importance":"low","after":["MT-6","MT-7"]}]
