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
