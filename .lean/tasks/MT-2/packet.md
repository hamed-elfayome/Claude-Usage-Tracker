<!-- source: .lean/plans/multi-team-packets.md lines 215-299 -->
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

**Validate:** `scripts/validate-clt.sh` (runs `xcodebuild test` automatically when full Xcode is present) `git diff --check` (coverage limit: see `multi-team.md`)
