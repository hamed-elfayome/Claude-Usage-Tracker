## Verdict        PASS — all 5 steps done, AC1-7 met and tested, gates green
## How it's going A — small, focused diff; one resolver drives picker and loader.
Tests are real (fail if resolver/hiding/%ld removed); locale test now covers 17 keys x 15 locales.
## Done well
- effectiveHistoryKey is pure and unit-tested for stale, valid, nil and single-pair cases
- Specifier changes match Int call sites (Int(...) and deleteAfterDays: Int?)
- Empty detail hidden in the view; layout test compares heights, not just no-crash
## Must fix
(none)
## Tests to add
(none)
## Hunter
Not run. Reviewer negative check: grep for `%d` in multiteam.ui values across 15 locales -> 0 hits.
## Improve later
- activeHistoryKey computed property has a deferred side effect (reset); consider moving to onAppear/onChange.
