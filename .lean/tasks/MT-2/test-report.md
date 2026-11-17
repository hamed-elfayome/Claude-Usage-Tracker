## Tester result
All green: 493 run, 491 ok, 0 failed, 2 skipped (pre-existing). Retest round 2: the verdict's placeholder-fallback case is already pinned by `testFollowedFallbackNeverPicksPlaceholder`, so no test was added; it fails when the fix is reverted.

## Suites run
- `scripts/validate-clt.sh` (worktree, unchanged code) → `Executed 493 tests: 491 ok, 0 failed, 2 skipped`, RC=0
- `git diff --check` (worktree) → clean, RC=0
- Mutant in a scratch copy (`/private/tmp/claude-501/-Users-kuke-Coding-Claude-Usage-Tracker--claude-worktrees-coding-architecture-ca52bf/6ed82cb8-67da-4969-a6cd-778a093952e9/scratchpad/mt2-mut-r2`, worktree untouched; the `unknownOrgId` exclusion removed from the followed-org fallback at `AccountRules.swift:276`) → `Executed 493 tests: 490 ok, 1 failed, 2 skipped`. Failing: `AccountRulesTests.testFollowedFallbackNeverPicksPlaceholder`. The copy's RC=129 comes from `git diff --check` in a non-git copy, a copy artifact.
- No UI or API in this packet, so no e2e/Playwright flow.
- Limit: no full Xcode, so the CLT path ran (`scripts/validate-clt.sh` coverage limit in `multi-team.md`).

## New tests
- None added this round. The verdict's "Tests to add" line is covered by `Claude UsageTests/AccountRulesTests.swift` `testFollowedFallbackNeverPicksPlaceholder` (builder, round 2):
  - State `[unknown-org (member, first in state order), A (followed, lastSeen 5 days), B, C]`, lists `[B,C]` 100 s apart (both ≥ 60 s debounce, same path as the verdict's t=0 and t=100).
  - Asserts `teamRemoved(A)` on the second call, `followedOrgId == "B"`, and the placeholder stays `.member`.
  - Fails under the mutant above, so it guards the fix. A duplicate with identical behaviour was not added.

## Bugs
No failing test in the current tree. Carried over from the round-1 report, not re-checked this round (code read only, no test):
1. `Claude Usage/Shared/MultiTeam/CredentialOrgParser.swift:21-24` (`account()`): a nested `oauthAccount` without `organizationUuid` hides a root `organizationUuid`.
   - Input: `{"organizationUuid":"org-t","oauthAccount":{"emailAddress":"a@example.com"}}`
   - Expected: `orgId(fromOAuthAccountJSON:)` returns `"org-t"` (packet step 1: "top level or nested").
   - Actual: `nil`, because `account()` returns the nested object whenever it exists.
   - Reproduce: call `CredentialOrgParser.orgId(fromOAuthAccountJSON:)` with the input above.
   - Severity: low.
2. Open "Improve later" items from the earlier verdict, not new: the L3 streak is not reset by a non-401 poll (`AccountRules.swift` ruleL), `ruleS` S2 candidate creation does not check `run.resolved` (`:351-357`), and the OAuth-only org added by T is named "Team" (`:289`).
