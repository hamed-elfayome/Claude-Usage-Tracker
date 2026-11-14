## Verdict
FAIL — two reproduced behaviour bugs in `AccountRules.swift` (a legacy `unknown-org` placeholder gets a spurious notifying `adminMove`; a Max→Pro shape is reported as `earlyReset` instead of `seatChange(inferred: true)`) plus a walkthrough `## Acceptance` that is not one line per criterion.

## How it's going
Grade B. The pure per-account design follows spec §6 closely (order U→L→M→T→S→R→X, per-pair precedence, no I/O or `Date()`), and every AC has a named test that asserts real outputs. The two defects are local to `AccountRules.swift` and small to fix; the handover is stale on its counts.

## Done well
- `AccountRules.apply` is pure; `CredentialOrgParser` never throws and reads root and nested `organizationUuid` (`CredentialOrgParser.swift:15-45`).
- The arch round-1 fixes are in the code: L3 needs `oauthUnauthorized` in the call (`AccountRules.swift:169-198`), ruleS sweeps pendings older than 30 min (`:311-316`), and the M followed-org fallback excludes `goneIds` (`:276`).
- Boundary tests are real: 60 s list debounce, 10 min membership window (inclusive), R thresholds (exactly half, drop of exactly 10), 5 min natural reset, S2 spread 1.3 and 5 min reset tolerance.
- The tester diff only adds (+120 in `AccountRulesTests.swift`, 0 deletions); no `XCTSkip`, `XCTExpectFailure`, `noqa` or `.only` added.
- Gate green (489 run, 487 ok, 0 failed, 2 skipped); `git diff --check` clean; only the four task files and `.lean/tasks/MT-2` are touched.

## Must fix
1. **`Claude Usage/Shared/MultiTeam/AccountRules.swift`, `ruleM` missing loop (about line 244):** a `unknown-org` placeholder is counted as missing and confirmed gone. Exclude it: `for org in run.state.orgs where org.status == .member && org.orgId != TrackedOrg.unknownOrgId && !listedIds.contains(org.orgId)`. U stays its only exit. Placeholders are real: `TeamTrackingMigration.swift:9` creates one for legacy profiles with no org id.
2. **`AccountRules.swift`, `windows()` (lines 365-366):** the API maps `seven_day_opus: null` and `seven_day_sonnet: null` to 0.0 (`ClaudeAPIService.swift:971-977`), and `ClaudeUsage` has no presence flag. Append the per-model windows only when the new value is > 0: `if new.opusWeeklyPercentage > 0 { w.append((prev.opusWeeklyPercentage, new.opusWeeklyPercentage, false)) }`, and the same for sonnet. `settled()` uses `windows()` too, so it inherits the rule. Spec §6 S2 says windows qualify "when present in both", and a per-model 0 after a value ≥ 5 is absent, not a drop.
3. **`.lean/tasks/MT-2/walkthrough.md`, `## Acceptance`:** replace the grouped line with 22 lines, one per criterion (AC1 … AC22), each naming its test function(s) and result. The current line is grouped, and the counts (473 ok, 475 run) are stale; the final run is 489 run, 487 ok, 0 failed, 2 skipped. Update the `## Tests` line to match.

## Tests to add
1. `testUnresolvedPlaceholderIsNeverConfirmedGone` (AccountRulesTests): state `[unknown-org, member, firstSeenAt 0]`, legacy key assigned, followed `unknown-org`; lists `[A, B]` at t=1000, 1100, 1200. Expected: only `teamAdded` A and B on call 1; no `adminMove` or `teamRemoved` for `unknown-org`; placeholder still `.member`; `followedOrgId == nil`; `confirmedRemovals` empty. Today call 2 emits `adminMove(unknown-org → A)`.
2. `testMaxToProShapeIsSeatCandidate`: previous `TeamFixtures.usage(session: 40, weekly: 20, opus: 30)`; sample `usage(session: 10, weekly: 5, opus: nil)` at t=100 → `pending.kind == .seatInferred`, no events. Same sample at t=130 → exactly one `seatChange(inferred: true)`, no `earlyReset`. Today call 2 emits `earlyReset(session, 40 → 10)`.
3. `testPerModelWindowsQualifyWhenPresent`: previous `(session 40, weekly 20, opus 30)`; sample `(session 20, weekly 8, opus 12)` at t=0 → `pending.kind == .seatInferred` (ratios 0.5, 0.4, 0.4; spread 1.25). Guards that the fix does not drop per-model windows that are present.

## Hunter
- **#1 unknown-org placeholder (major): CONFIRMED.** Harness rebuilt with `swiftc` from the worktree's `AccountRules.swift`, `TeamTrackingModels.swift`, `CredentialOrgParser.swift`, `ClaudeUsage.swift` plus stubs. Call 2 emits `adminMove(unknown-org → A)` and sets `followed=A`; call 3 drops the placeholder with no event. → Must fix 1.
- **#2 Max→Pro null-as-zero (major): CONFIRMED.** Call 1 leaves `pending = earlyReset(session)`; call 2 emits `earlyReset` (notifies). The control with no opus gives `seatInferred` pending on call 1 as expected. → Must fix 2. The packet's per-model rule omitted presence; spec §6 "present in both" governs.
- **#3 L3 streak survives a non-401 poll (minor): CONFIRMED** (401, flagless poll, 401 → `needsLogin` + `loginLost`). Not blocking; see Improve later.
- **#4 X expiry on the last-seen clock (minor): CONFIRMED behaviour, REJECTED as a defect.** Expiry in the same call as the confirmed removal (16 days offline) follows §6 X and AC18 ("`lastSeenInListAt` 15 days + 1 s ago → removed"). Spec §3's "auto-deleted after 15 days" is ambiguous; see Improve later.

## Improve later
- Spec §3 vs §6 X: decide whether `old` gets a grace period from becoming old; then align §3 and AC18 (architect).
- L3 "2 consecutive polls" (spec §6) vs the counter, which only resets on an accepted sample or fingerprint change: decide whether a non-401 poll resets the streak.
- `CredentialOrgParser.account()` (`:21-24`): a nested `oauthAccount` without an org id hides a root `organizationUuid`. The packet says "top level or nested"; fall back to the root.
- T names an OAuth-only org "Team" (`AccountRules.swift:289`) because `AccountObservation` has no org-name field. MT-3 must pass the name in.
- S2 candidate creation (`:351`) does not check `run.resolved`, contradicting the walkthrough's invariant. Check it, or fix the walkthrough sentence.
- `ruleL` keeps the first `needsLogin` reason while blocked; `unreachable` pairs are never revived by a listing (spec silent; confirm intent).
- The `xcodebuild` path was not run (no Xcode in this environment); the CLT path is the only evidence.
