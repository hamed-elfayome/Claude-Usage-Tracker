## Summary
TeamsSectionView (popover Teams section), history org picker, Team tracking toggle, Google sign-in hint, 17 `multiteam.ui.*` strings in 15 locales.
Pure helpers (canMakeCurrent, canDelete, detail, historyChoices, defaultHistoryKey) are static on TeamsSectionView and tested.
## Changes
- MenuBar/TeamsSectionView.swift (new): view + pure helpers.
- UsageHistoryView.swift: Picker when >1 pair; load/export via forKey: with selected key, else the UUID calls. No reset call exists in this view.
- ManageProfilesView.swift: SettingToggle bound to @AppStorage(TeamTrackingSettings.enabledKey).
- PersonalUsageView.swift: google_hint caption under the sign-in button.
- 15 Localizable.strings: new keys appended (English everywhere).
- UsageTests/TeamsSectionViewTests.swift (new).
## Acceptance
1,2 met (testThreeRowsTwoEventsLayOut, testNeedsLoginNoEventsAndNilHeadroom); 3 testCanMakeCurrent; 4 testCanDelete; 5 testHistoryChoices; 6 testDefaultHistoryKeyIsFollowedOrg; 7 met by code (@AppStorage(TeamTrackingSettings.enabledKey)) + testToggleKey; 8 testUIKeysExistInEveryLocalization; 9 met, only Files-list paths changed (git status); 10 met.
## Flow
Caller (MT-7) passes TeamRow.build rows + TeamRow.recentEvents; callbacks go to the tracker. History view reads profile.orgTracking via historyChoices.
## Tests
TeamsSectionViewTests, 10 tests, via scripts/validate-clt.sh: "Executed 482 tests: 480 ok, 0 failed, 2 skipped" (2 skips pre-existing). git diff --check clean.
## Edge cases
Long names truncated (lineLimit 1, tested); nil headroom/session omitted; "min ago" only >15 min. Not handled: picker selection persistence across launches.
## Shortcuts
none
## Lessons
Do not run validate-clt.sh twice concurrently: both write build/clt and the first fails. Delete build/ afterwards.
