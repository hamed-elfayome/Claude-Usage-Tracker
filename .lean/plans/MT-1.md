### MT-1 — Team tracking data model, stores, migration, pair-keyed history, shared fixtures

Size: M
Risk: high
Importance: high
After: MT-0

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

**Validate:** `scripts/validate-clt.sh` (runs `xcodebuild test` automatically when full Xcode is present) `git diff --check`

**Coverage limit:** without Xcode the harness does not build the widget extension, the asset catalog or other resources, and compiles DynamicNotchKit/Sparkle against stubs; one full `xcodebuild` build+test run is required at release time (see `multi-team.md`).
