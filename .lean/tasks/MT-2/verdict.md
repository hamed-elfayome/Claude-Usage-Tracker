## Verdict
PASS — grade B (round 2 review, sonnet-medium). Written by the boss from the reviewer's returned result; the reviewer did not update this file itself.
## How it's going
Round 2 fix (sonnet-high) excludes `TrackedOrg.unknownOrgId` in the rule M followed-org fallback, the remaining selection site the round 1 fix missed.
## Evidence
- Reviewer read the round-2 diff: fallback in AccountRules.swift now excludes the placeholder; new test testFollowedFallbackNeverPicksPlaceholder covers it.
- Gate rerun: scripts/validate-clt.sh executed 493 tests, 0 failed, 2 skipped (rc=0); git diff --check clean.
- Reviewer's own validate rerun hit its 120 s tool limit and did not finish (gate rerun is the passing evidence).
## Must fix
- none
## Hunter
- 2 minor findings, non-blocking.
## Lesson
When fixing a placeholder-exclusion bug, grep every selection site (loops and fallbacks) for the placeholder id, not just the one reported.
