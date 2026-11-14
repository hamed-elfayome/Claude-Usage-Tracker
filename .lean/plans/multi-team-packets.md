### MT-1 — Team tracking data model, stores, migration, pair-keyed history, shared fixtures

Size: M
Risk: high
Importance: high

**Goal:** Add the v2 data model (spec `docs/specs/multi-team-tracking.md` §3, copy the types exactly), store
per-account state on `Profile` and global state in its own store, migrate existing profiles without data loss
(§9, R10), key `UsageHistoryService` by string so each pair has its own history, and add the shared test
fixtures every later packet uses.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/TeamTrackingModels.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamTrackingStore.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamTrackingMigration.swift`
- `Claude Usage/Shared/Models/Profile.swift` (stored property, `init`, `CodingKeys` :149-167, `init(from:)` :169-205, `encode(to:)` :207+)
- `Claude Usage/Shared/Services/ProfileManager.swift` (`loadProfiles()` :30-58; add two methods next to `saveClaudeUsage` :434)
- `Claude Usage/Shared/Services/UsageHistoryService.swift` (411 lines; cache :38, init :46, dir :58-69, file URL :71-72, record* :182-300, getters :306+)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (all 15 language folders)
- NEW `Claude UsageTests/Fixtures/TeamFixtures.swift`
- NEW tests `Claude UsageTests/TeamTrackingModelsTests.swift`, `TeamTrackingMigrationTests.swift`, `UsageHistoryKeyTests.swift`

New `.swift` files join the targets automatically. Do not edit `project.pbxproj`.

**Steps**
1. `TeamTrackingModels.swift`: the §3 types `UsageWindow`, `SeatFingerprint`, `PairStatus`, `RoundReading`,
   `PendingChange`, `TrackedOrg` (+ `static let unknownOrgId = "unknown-org"`), `AuthState`,
   `OrgTrackingState`, `PairRef`, `TeamEvent` (+ `Kind`), `TeamTrackingGlobalState`. All `Codable, Equatable`
   (synthesized). Add `OrgTrackingState.empty` and `TeamTrackingGlobalState.empty`, and
   `mutating func appendEvent(_:)` on the global state (insert at 0, cap 50). Add helpers
   `OrgTrackingState.org(_ id:) -> TrackedOrg?` and `mutating func updateOrg(_ id:, _ body: (inout TrackedOrg) -> Void)`.
2. `TeamEvent`: `init(kind:names:date:id:)` with defaults `Date()` / `UUID()`. Computed `title`, `body`,
   `notifies` exactly as spec §3 (keys `multiteam.event.<case>.title|body`; names via `names[id] ?? String(id.prefix(8))`;
   `%.0f` for percents; window names "5-hour"/"weekly"). `body` names the account(s); `groupMove` body lists
   accounts with another target, "Not moved: …", "Not checked: …" (omit empty parts). Also key
   `multiteam.login_again` = "Log in again" and `multiteam.not_signed_in` = "Not signed in".
3. Every new key in `en.lproj/Localizable.strings` AND, with the same English value, in every other
   `*.lproj/Localizable.strings` (no fallback to English otherwise).
4. `TeamTrackingStore.swift`:
   - `enum TeamTrackingSettings { static let enabledKey = "multiTeam.enabled"; static func isEnabled(_ d: UserDefaults = .standard) -> Bool }` (default false).
   - `final class TeamTrackingGlobalStore { init(defaults: UserDefaults = .standard); func load() -> TeamTrackingGlobalState; func save(_:) }`,
     key `multiTeam.globalState`, JSON; missing or corrupt → `.empty`.
5. `Profile`: `var orgTracking: OrgTrackingState?` (nil default), `CodingKeys` case, decode with
   `(try? c.decodeIfPresent(OrgTrackingState.self, forKey: .orgTracking)) ?? nil`, `encodeIfPresent`. Not a secret.
6. `TeamTrackingMigration`:
   - `static func migrate(_ profile: Profile, now: Date = Date()) -> Profile` per spec §9. Parse
     `oauthAccountJSON` with `JSONSerialization` (top-level or nested `oauthAccount`), never throw.
   - `static func pairHistoryKey(profileId: UUID, orgId: String) -> String` → `"\(profileId.uuidString)_\(orgId)"`.
7. `ProfileManager`: in `loadProfiles()` map profiles through `migrate`; save once via `profileStore.saveProfiles`
   if any changed. Add `func updateOrgTracking(_ state: OrgTrackingState, for profileId: UUID)` and
   `func updateOrganizationId(_ orgId: String?, for profileId: UUID)`; both update `profiles`, `activeProfile`
   when it matches, and save (follow `saveClaudeUsage` :434).
8. `UsageHistoryService`: internal storage keyed by `String` (cache, file `usageHistory_<key>.json`, defaults
   `lastSessionRecordTime_<key>` / `lastWeeklyRecordTime_<key>`). Public `forKey:` variants of `loadHistory`,
   `saveHistory`, `recordSessionReset`, `recordWeeklyReset`, `recordSessionPeriodic`, `recordWeeklyPeriodic`,
   `getSessionSnapshots`, `getWeeklySnapshots`, `exportToFile` if it takes a profile id; plus
   `deleteHistory(forKey:)` (file, cache entry, both defaults keys). Every UUID method keeps its signature and
   delegates with `profileId.uuidString`. Internal `init(defaults: UserDefaults, directory: URL)` for tests;
   `shared` unchanged.
9. `TeamFixtures.swift` (enum `TeamFixtures`, static strings and builders), contents per spec §13:
   org lists `orgsAB`, `orgsB`, `orgsABC`, `orgsAStandard`, `orgsAPremium` (`rate_limit_tier` "default_team_standard"
   vs "default_team_premium"), `orgsAPIOnly` (no `chat`); `usageJSON(session:weekly:sessionReset:weeklyReset:opus:)`
   (ISO8601 with fractional seconds, `five_hour`/`seven_day`/`seven_day_opus` objects with `utilization` and
   `resets_at`); `usageNoFiveHour`; `usage(...) -> ClaudeUsage` decoding through
   `ClaudeAPIService().parseUsageResponse(_:)`; `credentialsOrgA`, `credentialsOrgB`, `credentialsNoOrg`
   (root `organizationUuid`, `claudeAiOauth.subscriptionType` "team"); `oauthAccountOrgA` (with
   `organizationName` "Team A"); `legacyProfileJSON` (encode a `Profile` built in code, then strip `orgTracking`).
10. Tests, then Validate.

**Acceptance criteria**
1. Legacy profile JSON without `orgTracking` → decodes, `orgTracking == nil`, other fields unchanged.
2. Profile JSON whose `orgTracking` is a corrupt object → decodes, `orgTracking == nil`, profile kept.
3. `TeamTrackingGlobalState` holding one event of every `TeamEvent.Kind` case → JSON round trip equal.
4. `appendEvent` 51 times → 50 events, newest first.
5. Global store with corrupt data under `multiTeam.globalState` → `load()` returns `.empty`.
6. migrate(anthropic, organizationId "A", claudeUsage U) → one org "A", `.member`, historyKey = profile UUID string, lastUsage U, `legacyHistoryKeyAssigned`.
7. migrate(organizationId nil, `oauthAccountJSON` = `oauthAccountOrgA`) → org from it, name "Team A".
8. migrate(nothing known) → org `unknown-org`, name "Team".
9. migrate on an already migrated profile → identical; on a `.codex` profile → unchanged.
10. `recordSessionPeriodic(for: uuid, …)` writes `usageHistory_<UUID>.json` in the injected directory.
11. `recordSessionPeriodic(forKey: "U_orgB", …)` writes `usageHistory_U_orgB.json`; the UUID file is untouched.
12. Two keys can each record in the same minute (throttle is per key).
13. `deleteHistory(forKey:)` removes the file and both defaults keys; other keys untouched.
14. `TeamEvent(kind: .adminMove(profileId: p, from: "a", to: "b"), names: ["a":"A","b":"B"]).title` == "Moved by admin: A → B"; `.teamAdded` → `notifies == false`.
15. `TeamFixtures.usage(session: 40, weekly: 20, …)` → parsed `sessionPercentage == 40`, `weeklyPercentage == 20`.
16. `TeamTrackingSettings.isEnabled` on a fresh suite → false.
17. Full existing suite passes.

**Tests:** XCTest with a temp directory and `UserDefaults(suiteName:)` removed in `tearDown`. Edge cases:
empty and malformed `oauthAccountJSON`; `claudeUsage == nil`; history key with `-` and `_`; unknown org id in
an event title (prefix fallback); `groupMove` with empty `notMoved`/`unchecked`.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-2 — Per-account event rules and credential-org parser (pure)

Size: M
Risk: normal
Importance: high
After: MT-1

**Goal:** Implement the per-account part of the event state machine (spec `docs/specs/multi-team-tracking.md`
§6: rules U, L, M, T, S, R, X) as one pure, fully tested function, plus pure parsing of the org and seat in
stored Claude Code credentials. No network, Keychain, singletons or `Date()`. The thresholds in §6 are
decisions: do not change them. Cross-account logic (current detection, group events) is MT-3, not here.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/AccountRules.swift`
- NEW `Claude Usage/Shared/MultiTeam/CredentialOrgParser.swift`
- NEW `Claude UsageTests/AccountRulesTests.swift`, `Claude UsageTests/CredentialOrgParserTests.swift`
- Read only: `MultiTeam/TeamTrackingModels.swift`, `TeamTrackingMigration.swift`, `Claude UsageTests/Fixtures/TeamFixtures.swift`,
  `Shared/Models/ClaudeUsage.swift`, `Shared/Models/UsageHistory.swift:326-335` (reuse `ResetDetection.tolerance`).

**Steps**
1. `CredentialOrgParser` (enum, static, never throws):
   - `orgId(fromCredentialsJSON:)`: root `organizationUuid`, else `claudeAiOauth.organizationUuid`; empty → nil.
   - `orgId(fromOAuthAccountJSON:)`, `orgName(fromOAuthAccountJSON:)` (top level or nested `oauthAccount`).
   - `seat(fromCredentialsJSON:)`: present non-empty `claudeAiOauth.rateLimitTier`, `claudeAiOauth.subscriptionType`
     joined by `|`, source `.credentials`; none → nil.
   - `seat(rateLimitTier:ravenType:billingType:)`: same join order, source `.orgList`; none → nil.
2. In `AccountRules.swift` define `OrgListEntry`, `AccountObservation` (fields as spec §6, all with defaults
   so tests set only what they need; `now` required), `ResetSnapshot { orgId, window, previous: ClaudeUsage }`,
   `ConfirmedRemoval { orgId, movedTo: String? }` and `AccountResult { state, events: [TeamEvent],
   resetSnapshots, confirmedRemovals, followedOrgId: String?, deletedHistoryKeys: [String], acceptedSamples: [String: ClaudeUsage] }`.
3. `enum AccountRules { static func apply(_ obs: AccountObservation, to state: OrgTrackingState, profileId: UUID, profileName: String, followedOrgId: String?) -> AccountResult }`.
   Order U → L → M → T → S → R → X; precedence per pair L > M > T > S > R. One private static func per rule.
4. Decisions the spec leaves to code:
   - New pair history key: `!legacyHistoryKeyAssigned` → `profileId.uuidString` and set the flag; else
     `TeamTrackingMigration.pairHistoryKey(profileId:orgId:)`.
   - Missing-count increments only when `obs.now − state.lastOrgListAt ≥ 60 s` or there was no previous list;
     set `lastOrgListAt = obs.now` after a successful non-empty list.
   - `usageMembershipFailures` sets `lastMembershipFailureAt = now` on that pair.
   - L3 uses `consecutiveOAuthUnauthorized` (+1 on `oauthUnauthorized`, 0 on any accepted sample) ≥ 2, and
     only when `hasSessionKey == false`.
   - While `needsLogin`: samples are accepted only if `credentialFingerprint` differs from the stored one or a
     sample/list succeeded — that is the restore signal (`loginRestored`). Store `credentialFingerprint` every run.
   - Samples for orgs that are not `member` are ignored (never revive an `old` pair from a stray sample).
   - Window presence: session = `hasSessionLimit` in both; weekly = `hasWeeklyLimit` in both. S2 per-model
     windows: `opusWeeklyPercentage`, `sonnetWeeklyPercentage` when previous ≥ 5.
   - When the S2 candidate test matches, R is not evaluated for that pair in that run.
   - Confirmed early reset → event + `ResetSnapshot` with the baseline. Natural reset → `ResetSnapshot` only.
   - Every accepted sample sets `lastUsage`, `lastSampleAt`, goes to `acceptedSamples`. Identity events set
     `baselineStartedAt = now`, `pending = nil`. Do not touch `roundReading` (MT-3/MT-6 own it).
   - Events carry `names` (org ids → names from tracked orgs and list entries; `profileId.uuidString` → `profileName`).
   - `followedOrgId` in the result is non-nil only when it must change (move target, first member after a
     removal without target, T's new org, U's rename of the followed org).
   - X runs every call (also with an empty observation).
5. Tests, then Validate.

**Acceptance criteria**
1. List [A,B] then [B] (≥ 60 s later) then [B] (≥ 60 s later), A followed → `adminMove(A→B)` on the third call; A `.old`, history key kept; `followedOrgId == "B"`; `confirmedRemovals == [(A, B)]`.
2. List [B] once + A had a membership failure 5 min earlier → `adminMove(A→B)` on that call.
3. List [B] once + `peerConfirmedRemovals == ["A"]` → A confirmed gone on that call.
4. List [A] then `orgList == nil` or `[]` → no membership change, no event.
5. A confirmed gone, no new org → `teamRemoved(A)`.
6. `old` A listed again → `.member`, `teamRejoined`, `notifies == false`, same historyKey.
7. New org C in the list → `.member`, `teamAdded` (silent), history key `<uuid>_C`.
8. OAuth-only (`hasSessionKey false`), `credentialOrgId` A → B → `teamChanged(A→B)`; A `.unreachable`; followed B.
9. Seat fingerprint `.orgList` std → premium → `seatChange(inferred: false)`; source `.credentials` → `.orgList` → no event.
10. No fingerprint; session 40→10, weekly 20→5, reset times unchanged; next sample 11/5 → `seatChange(inferred: true)`; next 40/20 instead → no event.
11. Session 60 → 5 with reset 3 h away; next sample 6 → `earlyReset(session, 60, 6)` + one `ResetSnapshot`; next 61 instead → nothing.
12. Session 60 → 0 when `prev.sessionResetTime ≤ now + 5 min` and reset moved → natural `ResetSnapshot`, no event.
13. Reset time moved 2 h, not due, no drop → no snapshot, no event.
14. `usageNoFiveHour` sample after a 60 % session → no session event.
15. Pending early reset older than 30 min → discarded, no event.
16. `refreshRejected` → `needsLogin`, `loginLost`; next call with a new fingerprint and a sample → `.ok`, `loginRestored` (silent).
17. `orgListAuthFailed` → `needsLogin`; OAuth-only 401 once → `.ok`; twice in a row → `needsLogin`.
18. `old` pair with `lastSeenInListAt` 15 days + 1 s ago → removed, key in `deletedHistoryKeys`, `oldTeamDeleted(manual: false)`; 14 days → kept; `member` idle 60 days → kept; `unreachable` 60 days → kept.
19. Pair `unknown-org` + list with only chat org A → renamed to A, same historyKey, no event.
20. Sample for an `old` org → ignored (no `lastUsage` change).
21. `CredentialOrgParser` reads root and nested `organizationUuid`, nil for garbage/empty JSON; seat join order as step 1.
22. Full suite passes.

**Tests:** one test per acceptance line 1–21, built from `TeamFixtures`. Edge cases: list with only an
API-only org; two new orgs in one list (newest `firstSeenAt` wins as target); A→B→C between two lists
collapses to `adminMove(A→C)` (R11); weekly-only plan; move and session drop in the same call → only the move.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-3 — Current-pair detection, saved-window projection, group-move event, Teams rows (pure)

Size: M
Risk: normal
Importance: high
After: MT-1

**Goal:** The cross-account pure logic: decide the current pair from a probe round (spec
`docs/specs/multi-team-tracking.md` §4), project saved windows after their reset (§5), build the one grouped
event for a group move (§6 "Grouped move"), and build the sorted rows the Teams list shows (§11). No network,
no singletons, `now` always injected.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/CurrentPairDetector.swift`
- NEW `Claude Usage/Shared/MultiTeam/PairView.swift`
- NEW `Claude Usage/Shared/MultiTeam/GroupMoveAggregator.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamRows.swift`
- NEW tests `Claude UsageTests/CurrentPairDetectorTests.swift`, `PairViewTests.swift`, `GroupMoveAggregatorTests.swift`, `TeamRowsTests.swift`
- Read only: `MultiTeam/TeamTrackingModels.swift`, `Claude UsageTests/Fixtures/TeamFixtures.swift`, `Shared/Models/ClaudeUsage.swift`.

Do not edit `AccountRules.swift`, `CredentialOrgParser.swift` (MT-2) or any Localizable file.

**Steps**
1. `CurrentPairDetector`:
   ```swift
   struct RoundCandidate { let pair: PairRef; let previous: RoundReading?; let latest: ClaudeUsage?; let latestAt: Date? }
   struct RoundInput { let now: Date; let current: PairRef?; let manualPickAt: Date?; let lastRoundAt: Date?; let candidates: [RoundCandidate] }  // candidates in (profile order, org order)
   struct RoundOutput: Equatable { let current: PairRef?; let switched: Bool; let readings: [PairRef: RoundReading]; let rises: [PairRef: Double]; let clearManualPick: Bool }
   enum CurrentPairDetector { static let minRise = 1.0; static let tieEpsilon = 0.05; static let staleAfter: TimeInterval = 450
     static func metric(_ u: ClaudeUsage) -> (percent: Double, reset: Date)
     static func rise(previous: RoundReading?, latest: RoundReading) -> Double?   // nil = re-baseline only
     static func evaluate(_ input: RoundInput) -> RoundOutput }
   ```
   Rules exactly as spec §4 (metric, rise, decision, manual pick: if `manualPickAt != nil` and
   (`lastRoundAt == nil` or `manualPickAt > lastRoundAt`) → readings only, no switch, `clearManualPick = true`).
   A candidate with `latest == nil` gets no reading and no rise. Same-window tolerance = `ResetDetection.tolerance`.
2. `PairView` (struct) with `static func make(usage: ClaudeUsage?, sampledAt: Date?, now: Date) -> PairView`:
   fields `sessionPercent: Double?` (nil without a 5-hour window), `weeklyPercent: Double?`, `sessionProjected`,
   `weeklyProjected`, `sessionLeft`, `weeklyLeft`, `headroom: Double?` — rules spec §5; clamp 0…100.
3. `GroupMoveAggregator.event(from orgId: String, trigger: UUID, triggerTarget: String?, peers: [UUID: PeerOutcome], names: [String: String], now: Date) -> TeamEvent`,
   `enum PeerOutcome: Equatable { case moved(to: String?), notMoved, unchecked }`. Builds `.groupMove(from:to:moves:notMoved:unchecked:)`
   with the trigger in `moves` and `to = mostCommonTarget(moves, trigger:)`;
   `static func mostCommonTarget(_ moves: [UUID: String?], trigger: UUID) -> String?` (ties → trigger's target).
4. `TeamRows`:
   ```swift
   struct TeamRow: Identifiable, Equatable { let id: String; let pair: PairRef; let profileName: String; let orgName: String
     let isCurrent: Bool; let view: PairView; let lastSampleAt: Date?; let state: State; let deleteAfterDays: Int?
     enum State: Equatable { case ok, needsLogin, notSignedIn, old, unreachable } }
   static func build(profiles: [Profile], global: TeamTrackingGlobalState, hasCredential: (Profile) -> Bool, now: Date) -> [TeamRow]
   ```
   Only anthropic profiles with `orgTracking`. Order (spec §11): current row; then `.ok` rows by headroom desc,
   weekly left desc, "profile · org" asc (nil headroom last); then `.needsLogin`/`.notSignedIn` by name; then
   `.old`/`.unreachable` by name. `deleteAfterDays` for `.old` = ceil((lastSeenInListAt + 15 d − now) / 1 d), min 0.
   `id` = `"\(profileId)_\(orgId)"`. `static func recentEvents(_ global:, limit: Int = 5) -> [TeamEvent]`.
5. Tests, then Validate.

**Acceptance criteria**
1. Current A (rise 0), B rises 3 → current B, `switched`.
2. B rises 3, C rises 5 → C. B rises 4, C rises 4 → current A kept. A rises 4, B rises 4 → A kept.
3. No rises (all < 1.0) → unchanged, `switched == false`; current nil and no rises → nil.
4. B previous reading 600 s old → B re-baselined, no rise, current unchanged.
5. B previous session reset differs from latest by 2 h, latest 7 % → rise 7.
6. Same window, latest lower than previous (early reset) → rise 0.
7. `manualPickAt` after `lastRoundAt` → no switch even if B rises 10; readings updated; `clearManualPick`.
8. Weekly-only usage (`hasSessionLimit false`) → metric uses weekly percent.
9. Candidate with `latest == nil` → keeps no reading; not chosen.
10. `PairView`: session 80 % with reset 1 min ago, sampled before it → session 0, projected, sessionLeft 100; sampled after the reset time → not projected.
11. `PairView`: weekly reset passed → weekly 0, projected, opus 0; headroom = min(left).
12. Group: trigger P → B, peers Q moved B, R notMoved, S unchecked → `moves` has P and Q, `notMoved [R]`, `unchecked [S]`; title "2 accounts moved: A → B".
13. Group: all moved with no target → title "N accounts removed from A".
14. Rows: current first even with less headroom; then headroom 50 before 30; equal headroom → higher weekly left first.
15. Rows: `needsLogin` account rows after all `.ok`; `old` rows last with `deleteAfterDays` 3 when last seen 12 days ago.
16. Rows: codex profile and profile without `orgTracking` → no rows.
17. `recentEvents` returns at most 5, newest first.
18. Full suite passes.

**Tests:** one test per line 1–17 with `TeamFixtures.usage(...)` and a fixed `now`. Edge cases: empty
candidates; current pair not among candidates; three-way tie with no current (first in order); usage > 100 %
(left clamped to 0); `lastSeenInListAt` nil on an `old` pair (use `firstSeenAt`).

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-4 — API signals: tier fields, 404/429 mapping with Retry-After, usage-only fetch

Size: S
Risk: normal
Importance: normal

**Goal:** Give the team tracker the API signals it needs without changing behaviour for existing callers:
optional seat-tier fields on the org list, a distinct "not found" error, `Retry-After` on 429, a 429 code on
the OAuth path, and a one-request usage fetch for probes. Spec `docs/specs/multi-team-tracking.md` §2 (status
mapping row), §6 (M, S1), §7.

**Files**
- `Claude Usage/Shared/Services/ClaudeAPIService+Types.swift` (`AccountInfo` :28-32)
- `Claude Usage/Shared/Services/ClaudeAPIService.swift` (1369 lines; touch only: next to `fetchUsageData(sessionKey:organizationId:)` :513-542, `fetchUsageData(oauthAccessToken:)` :545-570, the status switch used by `performRequest` :807-866)
- NEW `Claude Usage/Shared/MultiTeam/AppError+MultiTeam.swift`
- NEW `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`

**Steps**
1. `AccountInfo`: add `var rateLimitTier: String? = nil`, `var billingType: String? = nil`,
   `var ravenType: String? = nil` and `CodingKeys` mapping `uuid`, `name`, `capabilities`, `rate_limit_tier`,
   `billing_type`, `raven_type`. `uuid`, `name`, `capabilities` stay as required as today. The memberwise
   `AccountInfo(uuid:name:capabilities:)` must still compile (`PreferredOrganizationTests`).
2. Extract the status switch of `performRequest` into
   `static func error(forStatus status: Int, data: Data, response: HTTPURLResponse, endpoint: String) -> AppError?`
   (nil for 2xx). `performRequest` throws its result. Same messages as today, except:
   - 404 → `AppError(code: .apiNotFound, …)` (was `.apiGenericError`);
   - 429 → `technicalDetails` gains a line `Retry-After: <seconds>` when the header holds integer seconds
     (HTTP-date values ignored).
3. Before step 2's 404 change: `grep -rn "apiGenericError" "Claude Usage"` and confirm no caller depends on a 404
   being generic; write the result in the walkthrough.
4. `fetchUsageData(oauthAccessToken:)`: 429 → `.apiRateLimited` with the same `Retry-After` line; 401/403 →
   `.apiUnauthorized` as today; everything else unchanged.
5. `func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage` next to
   `fetchUsageData(sessionKey:organizationId:)`: one `performRequest` to `/organizations/<id>/usage`, then
   `parseUsageResponse`. No overage/credit/spend calls.
6. `AppError+MultiTeam.swift`: `extension AppError { var retryAfterSeconds: TimeInterval?` (parses the
   `Retry-After:` line, must be ≥ 0), `var isCloudflareChallenge: Bool { code == .apiServiceUnavailable }`,
   `var isMembershipFailure: Bool { code == .apiUnauthorized || code == .apiNotFound }`,
   `var isRateLimited: Bool { code == .apiRateLimited } }`.
7. Tests, then Validate.

**Acceptance criteria**
1. Decoding `[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":"b","raven_type":"team"}]` → three fields set.
2. The same JSON without the three fields → nil fields, no error.
3. `error(forStatus: 404, …)` → `.apiNotFound`, `isMembershipFailure == true`.
4. `error(forStatus: 429, …)` with header `Retry-After: 120` → `.apiRateLimited`, `retryAfterSeconds == 120`, `isRateLimited`.
5. 429 without the header, or with `Retry-After: abc` → `retryAfterSeconds == nil`.
6. 403 with a body containing "Just a moment" → `.apiServiceUnavailable`, `isCloudflareChallenge`, not a membership failure.
7. 401 plain → `.apiUnauthorized`, `isMembershipFailure`.
8. 200 → nil; 500 → `.apiServerError` (as today).
9. `fetchUsageOnly` calls `performRequest` exactly once (code reading, noted in the walkthrough).
10. `grep` result of step 3 recorded; no behaviour change for other callers besides 404.
11. Full suite passes, including `PreferredOrganizationTests` and `ClaudeAPIServiceParsingTests`.

**Tests:** build `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)` directly, no network. Edge cases:
`Retry-After: 0`, `cf-mitigated` header with 401, lower-case `retry-after` header name.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

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

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-6 — TeamTracker: probe rounds, org lists, detection, group moves, persistence, history, events

Size: L
Risk: high
Importance: high
After: MT-2, MT-3, MT-4, MT-5

**Goal:** One `@MainActor` tracker that runs the whole follow model for anthropic profiles: org lists, probe
rounds, per-account rules (MT-2), current detection and group events (MT-3), scheduling and backoff (MT-5),
persistence of `orgTracking` and global state, per-pair history, invariants 2–3, notifications through a
protocol, and the contract the menu bar loop uses (MT-7). No edits to MenuBarManager or any view here.
Spec `docs/specs/multi-team-tracking.md` §3–§7, §10, §12 — read them first.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/TeamTracker.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamTrackerAdapters.swift`
- NEW `Claude UsageTests/TeamTrackerTests.swift` (fakes inside or in NEW `Claude UsageTests/Fixtures/TeamTrackerFakes.swift`)
- Read only: all `Claude Usage/Shared/MultiTeam/*.swift`, `Claude UsageTests/Fixtures/TeamFixtures.swift`,
  `Shared/Services/ProfileManager.swift` (`updateOrgTracking`, `updateOrganizationId`, `saveClaudeUsage`),
  `Shared/Services/UsageHistoryService.swift` (`forKey:` API), `Providers/Anthropic/AnthropicUsageProvider.swift:37-95`.

**Steps**
1. Protocols (in `TeamTracker.swift`):
   ```swift
   protocol TeamUsageFetching { func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo]
     func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage
     func fetchUsageViaProvider(_ profile: Profile) async throws -> ClaudeUsage }        // OAuth-only probes
   protocol TeamCredentialReading { func sessionKey(for p: Profile) -> String?; func hasCredential(_ p: Profile) -> Bool
     func credentialOrg(for p: Profile) -> (orgId: String?, seat: SeatFingerprint?); func fingerprint(for p: Profile) -> String? }
   @MainActor protocol TeamProfileStore { var trackedProfiles: [Profile] { get }; var activeProfileId: UUID? { get }
     func updateOrgTracking(_ s: OrgTrackingState, for id: UUID); func updateOrganizationId(_ o: String?, for id: UUID)
     func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID) }
   protocol PairHistoryRecording { /* the forKey: record*Periodic, record*Reset and deleteHistory(forKey:) of MT-1, same parameters */ }
   @MainActor protocol TeamEventNotifying { func post(_ event: TeamEvent, profiles: [Profile]) }
   ```
2. Adapters (`TeamTrackerAdapters.swift`): `ClaudeAPITeamFetcher` (wraps `ClaudeAPIService.fetchAllOrganizations(sessionKey:)`,
   `fetchUsageOnly`, and `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)`); `StoredCredentialReader`
   (session key = `profile.claudeSessionKey`; credential org/seat via `CredentialOrgParser` on `cliCredentialsJSON`,
   else `oauthAccountJSON`; fingerprint = first 16 hex chars of SHA256 (CryptoKit) of session key + `claudeAiOauth.refreshToken`;
   never logged); `extension ProfileManager: TeamProfileStore` (anthropic profiles only); `extension UsageHistoryService:
   PairHistoryRecording`; `NoopTeamEventNotifier`. Keychain reads: none.
3. `@MainActor final class TeamTracker: ObservableObject` with
   `init(store:fetcher:credentials:history:notifier:globalStore:policy:clock:random:)`, `static let shared`
   (real adapters, `NoopTeamEventNotifier`, `TeamTrackingGlobalStore()`), `var notifier` settable. Public contract
   exactly spec §10 plus `internal func tick(now: Date) async` for tests.
4. `start()`: no-op unless `TeamTrackingSettings.isEnabled()`; `scheduler.start(now)`; a `Task` loop calling
   `tick(now: clock())` then sleeping `policy.tick`. `stop()` cancels it and bumps a `generation` counter; any
   async result whose generation is stale is dropped before persisting. Ticks never overlap (`isTicking`).
5. `tick(now:)` order: (a) register/unregister accounts in the scheduler (`hasOrgList` = has session key); (b) repair
   `current` by the start rule (§4); (c) due lists via `BoundedTaskRunner` (cap 4, 1 per account) → observation
   with `orgList` (map `AccountInfo` → `OrgListEntry`, seat via `CredentialOrgParser.seat(rateLimitTier:ravenType:billingType:)`,
   `canChat = capabilities.contains("chat")`; non-CF 401/403 → `orgListAuthFailed`; Cloudflare → no observation;
   outcome to `scheduler.listFinished`); (d) if `isRoundDue` → round (step 6); (e) save global state if changed.
6. Round: `roundStarted`; eligible saved pairs (spec §4) probed via runner — session key → `fetchUsageOnly`,
   OAuth-only credential org → `fetchUsageViaProvider` (a result with `lastUpdated ≤ lastSampleAt` is no sample).
   Errors: `isRateLimited` → `scheduler.record(.rateLimited(retryAfterSeconds))`; non-CF `isMembershipFailure` →
   `usageMembershipFailures`, and `.apiUnauthorized` on OAuth-only → `oauthUnauthorized`; others `.failed`.
   Then one `AccountRules.apply` per tracked account (empty samples allowed; X runs), then for accounts with a
   membership failure `forceList` + inline list + apply again. Then `CurrentPairDetector.evaluate` over every
   `member` pair of `.ok` accounts (current's candidate = its `lastUsage` if `lastSampleAt > lastRoundAt`); write
   `roundReading`s, `lastRoundAt`, clear `manualPickAt` when told, apply switch effects (§4).
7. One private `process(profileId:result:)` for every path: `updateOrgTracking`; `followedOrgId` → for session-key
   accounts `updateOrganizationId`, and `saveClaudeUsage(followed pair lastUsage)`; `resetSnapshots` →
   `record*Reset(forKey: historyKey, …)` with the previous window's reset time, skip that window's periodic
   record; periodic records for every accepted sample; probe sample of the followed pair of a non-current account →
   `saveClaudeUsage` + `onSample`; `deletedHistoryKeys` → `deleteHistory`; events → `global.appendEvent`, post when
   `notifies` (`nowOn`: only if ≥ 900 s since `lastSwitchNotificationAt`, then set it); if the current pair became
   `old` → current = move target (or nil), `onCurrentChanged`.
8. Group move (§6): when `confirmedRemovals` has org A and peers exist, withhold this account's move/removed event
   for A, force peer lists (`bypassDebounce: true`) through the runner with `timeout: 60`, apply each with
   `peerConfirmedRemovals = [A]`, withhold their A events, map outcomes to `PeerOutcome`, append and post one
   `GroupMoveAggregator.event(...)`.
9. `liveTarget`, `ingestLive`, `makeCurrent`, `deleteOldPair`, `reportRefreshRejected` per spec §10 and §4/§6.
   `ingestLive` success never calls `saveClaudeUsage` (the loop does); failures map like step 6; a membership
   failure forces the list in a `Task`.
10. Tests with fakes (fetcher returning `TeamFixtures` bodies, credential reader, in-memory store, recording history
    and notifier, `UserDefaults(suiteName:)` global store, controllable clock, fixed random), then Validate.

**Acceptance criteria**
1. Detected switch: current (P1, A) idle; (P2, B) probe 10 % → 14 % over two rounds → current (P2, B), P2 `organizationId == "B"`, one "Now on" notification; a second switch 5 min later → event logged, no notification.
2. Manual pick: `makeCurrent((P3, C))` → current immediately, no notification; the next round with P1 rising does not switch; the round after does.
3. Admin move: probe of (P1, A) returns 404, inline list [B] → `adminMove(A→B)`, A `.old` and never probed again, P1 `organizationId == "B"`, current follows to (P1, B) when A was current.
4. Group move: P1…P5 share A; P1's list confirms A gone → peers listed at once; P2–P4 moved to B, P5 still lists A → exactly one notification "4 accounts moved: A → B", P5 in `notMoved`; no individual `adminMove` events.
5. Group move with a peer backing off → that peer in `unchecked`.
6. Seat change: list `orgsAStandard` then `orgsAPremium` → one `seatChange` notification.
7. Early reset: live samples 60 → 5 → 6 (reset 3 h away) via `ingestLive` → one `earlyReset` notification and one session reset in history under the pair's key.
8. 429: probe `.apiRateLimited` with Retry-After 120 → account skipped by the next round and lists; `liveTarget()` nil when the current account is backing off.
9. Login loss: `reportRefreshRejected(P1)` → `needsLogin`, no probes/lists for P1, `liveTarget()` nil if current; fingerprint changes + successful probe → `.ok`, no notification.
10. Migration: a legacy profile records periodic history under `profile.id.uuidString`.
11. Old team: `old` pair last seen 16 days ago → deleted at the next round, `deleteHistory` called with its key; `deleteOldPair` on a `member` pair → false.
12. Invariant 3: a probe sample of a saved non-followed org never changes `claudeUsage`; of the followed org of a non-current account it does; `ingestLive` never does.
13. `stop()` during a round → nothing persisted from that round.
14. Tracking disabled → `start()` does nothing, `liveTarget()` nil.
15. Full suite passes.

**Tests:** one test per line 1–14. Edge cases: profile deleted while a probe is in flight (no store write);
Cloudflare 403 on a probe → no event, no list; two profiles with the same org id stay independent; no anthropic
profiles → tick is a no-op.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-7 — Wire the tracker into the menu bar loop, popover, token refresh and notifications

Size: M
Risk: high
Importance: high
After: MT-6, MT-8

**Goal:** Make the running app follow the current pair when Team tracking is on: the existing 30 s loop polls
only the current pair and hands every sample to the tracker, the menu bar and popover show the current account
without activating it (no Claude Code credential writes), per-pair history replaces the old reset checks for
anthropic profiles, `invalid_grant` reaches the tracker, team events become notifications, and the Teams section
appears in the popover. With tracking off every code path is exactly today's. Codex profiles never change.
Spec `docs/specs/multi-team-tracking.md` §4 (switch effects), §7, §10, §11.

**Files**
- `Claude Usage/MenuBar/MenuBarManager.swift` (1924 lines; touch only `setup()` :121, `cleanup()` :261, the initial
  usage reads :169 and :360-375, single-mode display :950-960, `refreshAllSelectedProfiles` :1007-1160,
  `refreshUsage` :1201-1418)
- `Claude Usage/MenuBar/PopoverContentView.swift` (viewed-profile fallbacks :130-145 and :206; insert after the insights block :262-266)
- `Claude Usage/Shared/Services/Providers/Anthropic/AnthropicUsageProvider.swift` (the `ensureFreshCredentials` call :54)
- `Claude Usage/Shared/Services/NotificationManager.swift` (add an extension at the end; posting like `sendAutoSwitchNotification` :308)
- NEW `Claude UsageTests/TeamEventNotificationTests.swift`
- Read only: `MultiTeam/TeamTracker.swift`, `TeamRows.swift`, `MenuBar/TeamsSectionView.swift`.

**Steps**
1. `MenuBarManager`:
   - `var menuBarProfile: Profile?` = when `TeamTracker.shared.isRunning`, the profile of `global.current` (if it
     still exists) else `profileManager.activeProfile`; when not running, `profileManager.activeProfile`.
   - `setup()`: `TeamTracker.shared.notifier = NotificationManager.shared`; `onCurrentChanged = { [weak self] _ in
     self?.refreshUsage() }` (also refresh the menu bar display); `onSample = { [weak self] id, usage in … }` writes
     the statusline cache exactly like :1287-1290 but only when `id == activeProfile?.id`; `start()`. Observe
     `UserDefaults.didChangeNotification` and start/stop the tracker when `TeamTrackingSettings.isEnabled()` flips,
     then refresh. `cleanup()`: `stop()`.
2. `refreshUsage` (single mode): `subject = menuBarProfile`. If tracker running and `subject.provider == .anthropic`:
   `guard let target = TeamTracker.shared.liveTarget(), target.profile.id == subject.id` else log, keep cached, return.
   Fetch with `fetchUsageForActiveProfile` when `subject.id == activeProfile?.id`, else
   `ProviderRegistry.service(for:).fetchUsage(for: subject)`. Inside this function replace reads of
   `profileManager.activeProfile` used for the fetched profile, `self.usage` and `saveClaudeUsage` with `subject`;
   keep the statusline block guarded to the active profile; keep auto-switch logic untouched. After success
   `ingestLive(profileId:orgId: target.orgId, result: .success, isCachedReading:)` and skip
   `checkAndRecordSessionReset`, `checkAndRecordWeeklyReset`, the periodic recorders and the `resetJustRecorded`
   bookkeeping; in `catch` `ingestLive(… .failure(error) …)`. Tracker off → today's code unchanged.
3. `refreshAllSelectedProfiles` (multi mode), tracker running: anthropic selected profiles that are not the current
   account → no fetch (render their `claudeUsage`); the current account is fetched even when not selected (not
   rendered); same liveTarget / ingest / skip-history pattern. Non-anthropic and tracker off → unchanged.
4. Single-mode display reads (:169, :360-375, :958) use `menuBarProfile` instead of `activeProfile`.
5. After each pass: if the shown account's `orgTracking?.authState` is `.needsLogin`, set `hasCredentialError = true`
   and `lastRefreshError = AppError(code: .apiUnauthorized, message: "multiteam.login_again".localized, …)`; do not
   clear it in the same pass.
6. `PopoverContentView`: the viewed-profile fallbacks use `manager.menuBarProfile` instead of
   `profileManager.activeProfile` (a click still overrides). After the insights block: when the tracker runs and
   `TeamRows.build(...)` returns ≥ 2 rows → `PopoverDivider()` + `TeamsSectionView(rows:events:now:onMakeCurrent:
   { TeamTracker.shared.makeCurrent($0) }, onDelete: { _ = TeamTracker.shared.deleteOldPair($0) })`. Observe
   `TeamTracker.shared` so rows refresh.
7. `AnthropicUsageProvider.fetchUsage(for:)`: pass `onRefreshRejected:` to `ensureFreshCredentials` that hops to the
   main actor and calls `TeamTracker.shared.reportRefreshRejected(profileId: profile.id)` (the tracker ignores it
   when not running). No other change to the chain.
8. `NotificationManager`: `extension NotificationManager: TeamEventNotifying`; `post(_:profiles:)` returns early unless
   `event.notifies` and at least one involved profile (event's account(s)) has `notificationSettings.enabled`;
   content from pure `static func teamEventContent(_ e: TeamEvent) -> (identifier: String, title: String, body: String)`
   (identifier `team-event-<id>`, title/body from the event); post like `sendAutoSwitchNotification`.
9. Tests, then Validate.

**Acceptance criteria**
1. Tracker off → `git diff` shows every changed branch guarded by `isRunning`/provider checks; existing tests green (walkthrough lists the guards).
2. Tracker on, single mode, current account ≠ active profile → the fetch uses `fetchUsage(for:)` for the current account; `activateProfile` is never called; the active profile's Claude Code credentials are not touched (code reading).
3. `liveTarget()` nil → no network fetch for that account in that pass; cached value stays.
4. Anthropic sample with tracker on → `ingestLive` called; `checkAndRecordSessionReset/WeeklyReset` and periodic recorders not called for it (code reading); Codex profile → old path unchanged.
5. Multi mode with 3 selected anthropic profiles → only the current account is fetched per pass.
6. `teamEventContent` for `adminMove(A→B)` → identifier `team-event-<uuid>`, title "Moved by admin: A → B".
7. `post` with `notifies == false`, or with every involved profile's notifications disabled → nothing posted (test through the early-return helper).
8. `ensureFreshCredentials` in `AnthropicUsageProvider` receives a non-nil `onRefreshRejected`.
9. Shown account `needsLogin` → `hasCredentialError == true`, banner text "Log in again".
10. Popover shows the Teams section only when the tracker runs and ≥ 2 rows exist (code reading).
11. Full suite passes.

**Tests:** `TeamEventNotificationTests` for lines 6–7 and a non-empty title for every `TeamEvent.Kind`. Edge cases:
group event where only one involved profile has notifications on (posted); event naming a deleted profile.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-8 — Teams UI: Teams section view, history org picker, tracking toggle, Google sign-in hint

Size: M
Risk: normal
Importance: normal
After: MT-3

**Goal:** Build the user-facing pieces as self-contained views fed by MT-3's pure `TeamRows` / `PairView`:
the popover "Teams" section (current + saved rows, projected marks, Make current, delete old team with a
confirm dialog, recent events), the history view's org picker, the Team tracking toggle (spec §11) and the
Google sign-in hint (§8, R14). The popover insertion and the tracker callbacks are wired in MT-7, so this
packet runs alongside MT-2/MT-4/MT-5/MT-6. Spec `docs/specs/multi-team-tracking.md` §5, §8, §11.

**Files**
- NEW `Claude Usage/MenuBar/TeamsSectionView.swift`
- `Claude Usage/Views/Settings/Profile/UsageHistoryView.swift` (`loadHistory` :176-183, export :185+ and any reset call)
- `Claude Usage/Views/Settings/App/ManageProfilesView.swift` (633 lines; add one toggle near the existing `SettingToggle`s :55-170)
- `Claude Usage/Views/Settings/Credentials/PersonalUsageView.swift` (783 lines; only the sign-in block :258-275)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (all 15 folders; new `multiteam.ui.*` keys only)
- NEW `Claude UsageTests/TeamsSectionViewTests.swift`
- Read only: `MultiTeam/TeamRows.swift`, `PairView.swift`, `TeamTrackingModels.swift`, `TeamTrackingStore.swift`,
  `MenuBar/PopoverContentView.swift` (style of `ContextualInsights` and `UsageRow` only).

Do not edit `PopoverContentView.swift`, `MenuBarManager.swift`, `NotificationManager.swift` or any `MultiTeam/*.swift` file.

**Steps**
1. `TeamsSectionView(rows: [TeamRow], events: [TeamEvent], now: Date, onMakeCurrent: (PairRef) -> Void, onDelete: (PairRef) -> Void)`:
   - Header "Teams" with a chevron; expanded state in `@AppStorage("popover.teamsExpanded")`, default true.
   - Row: "<profile> · <team>"; a "Now" badge when `isCurrent`; "5h n% left" (omit when nil) and "Week n% left";
     a small "projected" caption after a projected window; "n min ago" when `lastSampleAt` is older than 15 min.
     `.needsLogin` → "Log in again" (`multiteam.login_again`) instead of numbers; `.notSignedIn` → "Not signed in".
     `.old`/`.unreachable` → dimmed, "Old team · deleted in N days" (`.old`) or "Old team" (`.unreachable`) and a
     Delete button.
   - Context menu and a trailing menu button on `.ok` non-current rows: "Make current" → `onMakeCurrent(row.pair)`.
   - Delete → `.confirmationDialog` "Delete old team <team> for <profile>? Its history is removed." with
     Delete (destructive) / Cancel; only Delete calls `onDelete`.
   - Below rows: up to 5 events (title + `RelativeDateTimeFormatter` relative to `now`).
   - Fonts/colours like `ContextualInsights`/`UsageRow`; fits the 280 pt popover width.
2. `UsageHistoryView`: when the profile has `orgTracking` with > 1 pair (any status, each has a `historyKey`), show
   a `Picker` (team names; `.old` labelled "(old)"), default = the profile's followed org (`organizationId`) pair,
   else the first. Load, export and reset through the `forKey:` API with the selected `historyKey`. With ≤ 1 pair
   or no `orgTracking`: exactly today's UUID calls.
3. `ManageProfilesView`: a `SettingToggle` "Team tracking (follow the account in use)" with a one-line description
   ("Detects which account and team you are using from rising usage; other teams are checked every 5 minutes."),
   bound to `@AppStorage(TeamTrackingSettings.enabledKey)`.
4. `PersonalUsageView`: under the "Sign in to Claude.ai" button, a secondary caption (key
   `multiteam.ui.google_hint`): "Google sign-in blocked? Sign in at claude.ai in your browser and paste the
   session key below, or use the Claude Code login. In the Google window, pick the right account." No logic change.
5. Every new string as `multiteam.ui.*` in all 15 `Localizable.strings` (English value everywhere).
6. Tests, then Validate.

**Acceptance criteria**
1. `TeamsSectionView` with 3 rows (current, saved projected, old) and 2 events hosts in an `NSHostingView` (width 280) and lays out without crashing.
2. Same with 0 events and a `.needsLogin` row → no crash.
3. `onMakeCurrent` is not offered for the current row nor for `.old`/`.needsLogin` rows (expose a pure `static func canMakeCurrent(_ row: TeamRow) -> Bool` and test it).
4. Delete is offered only for `.old`/`.unreachable` (`static func canDelete(_:) -> Bool`, tested).
5. Pure `static func historyChoices(for profile: Profile) -> [(key: String, label: String)]`: 2 pairs → 2 choices, old one labelled "(old)"; 1 pair → empty (picker hidden); no `orgTracking` → empty.
6. Default history choice = followed org pair (test through a pure helper).
7. The toggle writes `multiTeam.enabled` (code reading in the walkthrough: `@AppStorage(TeamTrackingSettings.enabledKey)`).
8. The Google hint key exists in all 15 `Localizable.strings` (test: load each `.lproj` bundle path's strings file and check the key, or a `grep -c` noted in the walkthrough).
9. No file outside the Files list changed (`git diff --stat` in the walkthrough).
10. Full suite passes.

**Tests:** `TeamsSectionViewTests` for lines 1–6 with `TeamRow` values built by hand (fixed `now`). Edge cases: very
long profile and team names (layout still within width; check no crash), a row with `view.headroom == nil`.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

### MT-9 — User docs and changelog for Team tracking

Size: S
Risk: normal
Importance: low
After: MT-7

**Goal:** Tell users what Team tracking does, how it decides the account in use, what each event means, how to
sign in with Google, and its limits. Spec `docs/specs/multi-team-tracking.md` §4, §6, §8, §11, §15.

**Files**
- `docs/profiles.md` (add a section; keep existing ones)
- `docs/troubleshooting.md` (two entries)
- `CHANGELOG.md` (under the top "Unreleased" heading; create it above the newest release if missing)

**Steps**
1. `docs/profiles.md`, new section "Team tracking (several accounts and teams)": how to turn it on (Settings →
   Profiles); the current account is detected from rising 5-hour usage, checked every 5 minutes, shown in the menu
   bar without switching any login; "Make current" in the Teams list; other teams are checked every 5 minutes and
   show "projected" after their reset time; old teams are deleted 15 days after they disappear (or by hand).
   Events, one plain sentence each: Now on account (team); Moved by admin; N accounts moved; Removed from team;
   Team changed; Seat changed / Limit size changed; Early reset; Log in again.
2. Same section, "Signing in with Google": the in-app sign-in may be blocked by Google; then sign in at claude.ai in
   your browser and paste the session key, or use the Claude Code login (one team only). Pick the right Google
   account in the Google window. Leave a line "Checked by the owner on <date>: in-app Google sign-in works / is blocked"
   with the date and result as `TBD (owner)`.
3. Limits subsection in plain words: the spec §15 bullets (switch seen up to 5 min late; using two accounts at once
   flips the current one; two changes between checks show as one; undocumented endpoints; seat change without a tier
   field may show as early reset; OAuth-only accounts see one team; statusline refreshes every 5 min when the Claude
   Code profile is not current). Include the request to capture a redacted `/api/organizations` response per seat
   type (Settings → Debug network log).
4. `docs/troubleshooting.md`: "It says Log in again" (re-sign in to claude.ai in Settings or run `claude /login`
   for that account; the app never logs in for you) and "The wrong account is shown" (use "Make current"; detection
   needs the first message on the new account).
5. `CHANGELOG.md`: "Added" bullet (Team tracking: follows the account in use, team events, Teams list) and
   "Changed" bullets (a shifted reset time without a usage drop is no longer recorded as a reset; HTTP 404 maps to
   "not found").
6. Plain English, short sentences. Validate.

**Acceptance criteria**
1. `docs/profiles.md` has the "Team tracking" section with all 8 events.
2. It states the 5-minute check, the 15-day old-team deletion and how to turn the feature on.
3. The Google sign-in paragraph names both fallbacks and has the `TBD (owner)` line.
4. The limits list contains the "two changes between checks show as one" sentence.
5. `docs/troubleshooting.md` has both entries.
6. `CHANGELOG.md` has the Added and Changed bullets under Unreleased.
7. No code file changed; full suite still passes.

**Tests:** none beyond the suite (docs only). Check links with `grep -n "](" docs/profiles.md` by eye.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`

