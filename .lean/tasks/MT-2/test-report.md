## Tester result
All green: 489 run, 487 ok, 0 failed, 2 skipped (skips pre-existing); 10 new tests.

## Suites run
- `scripts/validate-clt.sh` before new tests → `Executed 479 tests: 477 ok, 0 failed, 2 skipped`, exit 0
- `scripts/validate-clt.sh` after new tests → `Executed 489 tests: 487 ok, 0 failed, 2 skipped`, exit 0
- `git diff --check` → clean, exit 0
- Limit: no full Xcode (`xcodebuild` requires Xcode), so the CLT path ran. Widget, asset catalog, Info.plist and `#Preview` bodies were not built (coverage limit in `multi-team.md`).
- No UI or API in this packet, so no e2e/Playwright flow.

## New tests
All in `Claude UsageTests/AccountRulesTests.swift` (10 functions, no production code touched).
- `testMissingDebounceBoundary`: 60 s list debounce. A list 59 s after the last one adds no miss; one exactly 60 s after does; the third list confirms the move.
- `testMembershipFailureWindowBoundary`: the 10 min membership-failure window is inclusive (600 s confirms, 601 s does not).
- `testEarlyResetCandidateThresholds`: R6 table. Exactly half (60→30) is a candidate, just above (60→31) is not; drop of exactly 10 (20→10) is a candidate, drop of 8 (15→7) is not.
- `testNaturalResetBoundary`: natural means now ≥ reset − 5 min, inclusive. At the edge the drop is a reset snapshot; 1 s earlier it is a candidate.
- `testSeatCandidateDirectionAndSpread`: S2 table. Upgrade (both windows double) is a candidate; mixed directions is not; max/min ratio 1.67 is rejected; 1.25 is accepted.
- `testSeatCandidateResetTimeTolerance`: S2 rejects a session reset moved more than 5 min; exactly 5 min is accepted.
- `testListRestoresLoginOnlyWhenNonEmpty`: a non-empty list restores `needsLogin` (spec L); an empty list does not and sends no events.
- `testPeerRemovalIgnoredWhenStillListed`: a peer's confirmed removal does not remove a pair still in this account's list (R13 step 4).
- `testTwoNewOrgsTieGoesToFirstListed`: packet edge case. Two new orgs share `firstSeenAt`; the move target tie goes to the first listed org (the builder's documented rule, now pinned).
- `testConfusableOrgIdIsADifferentOrg`: tracked `"org-\u{0430}"` (Cyrillic a) and listed `"org-a"` (Latin) are different orgs; the look-alike is not merged.

Not added (10-test budget): pending exactly 30 min; old-team expiry exactly 15 days; non-object `claudeAiOauth` inputs to the parser; OAuth-only account ignores a stray org list.

Mutation check was not run: it would mean editing production code, which is outside the tester's remit. Each boundary test asserts both sides of its threshold, so a flipped comparison fails one side.

## Bugs
Confirmed by a failing test: none.

Observations for the builder or architect (found by reading the code; none is reproduced by a test, because the spec or packet does not settle the expected behaviour):
1. `Claude Usage/Shared/MultiTeam/CredentialOrgParser.swift:21-27`: `account()` returns the nested `oauthAccount` whenever it exists, so a root-level `organizationUuid` is ignored when a nested `oauthAccount` without one is also present. Input `{"organizationUuid":"org-t","oauthAccount":{"emailAddress":"a@example.com"}}` gives nil; packet step 1 reads "top level or nested". Low severity; the shapes Claude Code writes are not affected as far as I can tell.
2. `Claude Usage/Shared/MultiTeam/AccountRules.swift:365-366, 376-378`: `ClaudeUsage` has no presence flag for Opus or Sonnet, so an absent per-model window reads 0 and the `new <= 1` guard rejects the S2 candidate. Spec §6 says windows qualify when present in both. Conservative (false negative). Repro by reading: previous `u(40,20)` with Opus 30, new `u(10,5)` with no Opus gives no `seatInferred`.
3. `Claude Usage/Shared/MultiTeam/AccountRules.swift:351-357` vs `:398`: S2 candidate creation does not check `run.resolved`; R does. A stale `seatInferred` pending (older than 30 min) plus a candidate-shaped sample in the same call creates a fresh pending. The summary's stated invariant says it should not. R's side drops the drop entirely in that case. Needs a decision.
4. `Claude Usage/Shared/MultiTeam/AccountRules.swift:289`: an OAuth-only org added by T is named "Team". `AccountObservation` has no org-name field, so `CredentialOrgParser.orgName` cannot reach the event. Note for MT-3: pass the name in, or the `teamChanged` event shows "Team".
5. `Claude Usage/Shared/MultiTeam/AccountRules.swift:169-173`: the L3 streak is not reset by a non-401 poll without an accepted sample. Input sequence 401, network error, 401 gives `needsLogin`. Spec §6 says "2 consecutive polls"; packet step 4 resets only on an accepted sample. Decision for the architect.
6. `Claude Usage/Shared/MultiTeam/AccountRules.swift:233-234`: a listed `unreachable` pair is never revived. Spec is silent. Confirm this is intended.
