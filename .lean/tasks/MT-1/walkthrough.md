## Summary
Added the v2 team tracking models, global store, migration, Profile.orgTracking, ProfileManager hooks, string-keyed UsageHistoryService, 15-language strings, fixtures and tests.
NOT VERIFIED BY xcodebuild (no Xcode here). Verified instead with a stub-XCTest harness over the real sources and tests (see Tests): 27 new tests pass.

## Changes
- Shared/MultiTeam/TeamTrackingModels.swift: spec §3 types, empty states, appendEvent (cap 50), org helpers, TeamEvent title/body/notifies.
- Shared/MultiTeam/TeamTrackingStore.swift: TeamTrackingSettings, TeamTrackingGlobalStore.
- Shared/MultiTeam/TeamTrackingMigration.swift: migrate, pairHistoryKey.
- Models/Profile.swift: orgTracking property, init param, CodingKeys, tolerant decode, encodeIfPresent.
- Services/ProfileManager.swift: migrate in loadProfiles (save once), updateOrgTracking, updateOrganizationId.
- Services/UsageHistoryService.swift: String-keyed storage + forKey: API, UUID wrappers in an extension, internal init(defaults:directory:), deleteHistory(forKey:).
- Resources/*.lproj/Localizable.strings (15): 32 new multiteam.* keys, English value.
- Tests: Fixtures/TeamFixtures.swift, TeamTrackingModelsTests, TeamTrackingMigrationTests, UsageHistoryKeyTests.

## Acceptance
Evidence rule: real `xcodebuild` is impossible on this machine (Command Line Tools only, no Xcode.app). Every "pass" below comes from a stand-in harness that compiled the real app sources plus the real test files and ran them (details under Tests). Nothing here is a real `xcodebuild test` result.
AC1 met (harness): TeamTrackingModelsTests.testLegacyProfileDecodesWithoutOrgTracking passed.
AC2 met (harness): TeamTrackingModelsTests.testCorruptOrgTrackingKeepsProfile passed.
AC3 met (harness): TeamTrackingModelsTests.testGlobalStateRoundTripEveryKind passed.
AC4 met (harness): TeamTrackingModelsTests.testAppendEventCapsAtFiftyNewestFirst passed.
AC5 met (harness): TeamTrackingModelsTests.testCorruptGlobalStoreReturnsEmpty passed.
AC6 met (harness): TeamTrackingMigrationTests.testMigratesKnownOrgWithUsage passed.
AC7 met (harness): TeamTrackingMigrationTests.testOrgFromOAuthAccount passed.
AC8 met (harness): TeamTrackingMigrationTests.testNothingKnownUsesUnknownOrg passed.
AC9 met (harness): TeamTrackingMigrationTests.testIdempotentAndCodexUntouched passed.
AC10 met (harness): UsageHistoryKeyTests.testUUIDMethodWritesLegacyFileName passed.
AC11 met (harness): UsageHistoryKeyTests.testKeyedMethodWritesPairFileOnly passed.
AC12 met (harness): UsageHistoryKeyTests.testThrottleIsPerKey passed.
AC13 met (harness): UsageHistoryKeyTests.testDeleteHistoryForKeyLeavesOthers passed.
AC14 met (harness): TeamTrackingModelsTests.testAdminMoveTitleAndNotifies passed (needs English strings from en.lproj; the harness bundles them).
AC15 met (harness): TeamTrackingModelsTests.testFixtureUsageParses passed.
AC16 met (harness): TeamTrackingModelsTests.testSettingsDefaultOff passed.
AC17 NOT PROVEN by xcodebuild. Harness: all 27 new tests + 59 existing tests from 6 existing files passed except SharedDataStoreTests.testShouldShowGitHubStarPrompt (86 run, 1 failure, in a file and service this change does not touch; most likely the harness's shared UserDefaults/bundle state). The full existing suite (about 30 files) was not run. Needs a machine with full Xcode.

## Flow
ProfileManager.loadProfiles -> TeamTrackingMigration.migrate -> profileStore.saveProfiles if changed. History: UUID API -> forKey: (uuidString) -> file usageHistory_<key>.json.

## Tests
Real command (packet Validate): `xcodebuild test ...` cannot run here: `xcode-select: error: tool 'xcodebuild' requires Xcode` (only /Library/Developer/CommandLineTools). No xcodebuild summary line exists.
Stand-in harness (scratch, not committed): swiftc -swift-version 5 -default-isolation MainActor (matching the project's SWIFT_DEFAULT_ACTOR_ISOLATION) compiled `Claude Usage/Shared/**` + `WidgetShared/**` (all of ProfileManager, UsageHistoryService, Profile, MultiTeam) with a ~15-line stub XCTest (XCTAssertEqual/True/False/Nil/NotNil/GreaterThan/LessThan, XCTUnwrap) and these real test files: TeamTrackingModelsTests, TeamTrackingMigrationTests, UsageHistoryKeyTests (+TeamFixtures), UsageHistoryTests, ProfileProviderTests, ClaudeAPIServiceParsingTests, DateExtensionsTests, SharedDataStoreTests. Excluded only files needing Sparkle/SwiftUI-macro plugins (UpdateManager, ErrorPresenter [stubbed], SupportReminderService) because Command Line Tools lack them. Ran inside a minimal .app bundle with en.lproj so `.localized` resolves, with `-AppleLanguages (en)`.
Result: exit 1, `FAILS: 1`, 86 tests run. All 27 new tests passed (TeamTrackingModelsTests 14, TeamTrackingMigrationTests 8, UsageHistoryKeyTests 5). The one failure: SharedDataStoreTests.testShouldShowGitHubStarPrompt (line 155), unrelated to this change.
Compile check: the whole `Claude Usage/Shared` tree typechecks and links with no redeclaration. The duplicate `updateOrganizationId(_:for:)` is gone (a single declaration remains, ProfileManager.swift:567; `grep -n "func updateOrganizationId"` shows one hit).
`git diff --check`: exit 0.
Round 4 root cause: the code defect (duplicate `updateOrganizationId`) was already fixed in round 3; the remaining FAIL is environmental. `xcodebuild -version` -> `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`; no Xcode.app anywhere (`/Applications`, `~/Applications`, Spotlight). Fresh check this round: `swiftc -typecheck -swift-version 5 -default-isolation MainActor` over all `Claude Usage/Shared/**` + `WidgetShared/**` (minus Sparkle-only UpdateManager) reports only the two `#Preview` macro-plugin errors in the untouched ErrorPresenter.swift (CLT has no PreviewsMacros plugin); zero errors in any changed or new file. `grep -rn "func updateOrganizationId" "Claude Usage"` -> 1 hit.
**Still required before merge: a real `xcodebuild test` on a machine with full Xcode.**

## Edge cases
Malformed/empty oauthAccountJSON, nil claudeUsage, keys with - and _, unknown org id prefix fallback, groupMove empty parts: tested. Added extra strings (window names, groupMove.removed/notMoved/unchecked, seatChange.inferred).

## Shortcuts
none

## Lessons
Tests assume English UI language for title strings. Test init of UsageHistoryService skips the legacy UserDefaults blob migration.
