## Summary
Added `TeamsSectionView.effectiveHistoryKey` so a deleted pair's history key is never shown or loaded, and reset a stale selection.
Switched every Int-formatted `multiteam.ui.*` value from `%d` to `%ld` in all 15 locales; the detail Text is hidden when it is empty.
Locale test now covers all 17 keys x 15 locales and rejects any bare `%d`.

## Changes
- Claude Usage/MenuBar/TeamsSectionView.swift: new `effectiveHistoryKey`; the detail Text is only shown when its string is non-empty.
- Claude Usage/Views/Settings/Profile/UsageHistoryView.swift: the picker getter and `activeHistoryKey` use the resolver; a stale non-nil selection is reset to nil (async, which triggers the existing onChange reload).
- Claude Usage/Resources/*.lproj/Localizable.strings (15 files): five_hour_left, week_left, min_ago, old_days use `%ld` (60 lines). All four call sites pass `Int`.
- Claude UsageTests/UsageHistoryKeyTests.swift: AC1-3 tests.
- Claude UsageTests/TeamsSectionViewTests.swift: test for 17 keys and no `%d`; test for an empty `.ok` row.

## Acceptance
1 met: testDeletedSelectedKeyFallsBackToDefault
2 met: testValidSelectedKeyIsKept
3 met: testSinglePairReturnsNil
4 met: testUIKeysExistInEveryLocalization (no `%d`, `%ld` present); grep finds 0 `%d`
5 met: testOkRowWithNoUsageHasEmptyDetailAndLaysOut (detail == [], and the row is shorter than a row with detail)
6 met: testUIKeysExistInEveryLocalization + testUIKeyListHas17Keys
7 met: validate-clt.sh reported 605 tests, 603 ok, 0 failed, 2 skipped (both skips were already there)

## Flow
UsageHistoryView.teamPicker getter → effectiveHistoryKey(selected, profile) → historyChoices/defaultHistoryKey. loadHistory → activeHistoryKey → the same resolver; if the selection is stale it schedules selectedHistoryKey = nil → onChangeCompat → loadHistory again with the default key (no change in the data that gets loaded).

## Tests
`bash scripts/validate-clt.sh`: 605 tests, 603 ok, 0 failed, 2 skipped. `git diff --check`: clean.

## Edge cases
Handled: the selected key is nil; the profile has one pair or no tracking (nil, picker hidden). The reset is deferred to the main queue so no state is written during a view update.
Not handled: none known.

## Shortcuts
none

## Lessons
none
