## Verdict
PASS - one resolver in TeamsSectionView drives both the picker getter and the loader, the empty-detail check sits in the view layer, and the specifier changes match the Int call sites.

## Must fix
(none)

## Notes
- `activeHistoryKey` is a computed property that also resets the selection asynchronously. This is acceptable because the write is deferred to the main queue and only fires when the selection is stale. If it ever causes extra reloads, move the reset into onAppear or onChange.
- The `effectiveHistoryKey` result is nil only when there is no picker, so the getter's `?? ""` fallback is never reached for a visible picker.
