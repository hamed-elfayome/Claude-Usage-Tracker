## Summary
Pure cross-account logic: CurrentPairDetector, PairView projection, GroupMoveAggregator, TeamRows.
No network/singletons; `now` injected.
## Changes
- Shared/MultiTeam/CurrentPairDetector.swift, PairView.swift, GroupMoveAggregator.swift, TeamRows.swift: new.
- Claude UsageTests/{CurrentPairDetector,PairView,GroupMoveAggregator,TeamRows}Tests.swift: new.
## Acceptance
AC1-17 met (one test each, see tests below); AC12 met: title reads "2 accounts moved: A → B" after the fix-round-1 edit to TeamTrackingModels.swift:123. AC18 met.
## Flow
Callers (later tasks) build RoundInput -> evaluate -> RoundOutput; TeamRow.build uses PairView.make per org.
## Tests
4 test files; scripts/validate-clt.sh: Executed 455 tests: 453 ok, 0 failed, 2 skipped.
## Edge cases
Empty candidates, current not in candidates, 3-way tie, >100% clamp, old pair without lastSeenInListAt: tested.
## Shortcuts
none
## Lessons
TeamEvent.groupMove title counts moves only (fix round 1: was moves+notMoved+unchecked, broke AC12).

## Fix round 1
TeamTrackingModels.swift:123 count = moves.count (outside Files list, approved). GroupMoveAggregatorTests asserts "2 accounts moved: A → B". validate-clt: Executed 455 tests: 453 ok, 0 failed, 2 skipped.
