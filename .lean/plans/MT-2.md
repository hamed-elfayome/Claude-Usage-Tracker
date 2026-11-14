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
