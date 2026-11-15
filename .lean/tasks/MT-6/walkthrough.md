## Summary
TeamTracker (@MainActor) runs the follow model: org lists, 300 s probe rounds, per-account rules, current detection, group moves, persistence, per-pair history, events.
All dependencies are protocols; real adapters live in TeamTrackerAdapters.swift. No view or MenuBarManager edits.

## Changes
- Claude Usage/Shared/MultiTeam/TeamTracker.swift: protocols + tracker (tick, round, lists, process, group move, spec §10 contract).
- Claude Usage/Shared/MultiTeam/TeamTrackerAdapters.swift: ClaudeAPITeamFetcher, StoredCredentialReader (SHA256 fingerprint), ProfileManager: TeamProfileStore, UsageHistoryService: PairHistoryRecording, NoopTeamEventNotifier.
- Claude UsageTests/TeamTrackerTests.swift: 19 tests (criteria 1-14 + edge cases).
- Claude UsageTests/Fixtures/TeamTrackerFakes.swift: fakes (fetcher with OAuth gate, credentials, store, history, notifier, ClockBox).

## Acceptance
1 met testDetectedSwitchNotifiesOnceThenFlapGuard; 2 met testManualPickHoldsOneRound; 3 met testAdminMoveFromProbe + testAdminMoveCurrentFollowsViaLiveFailure;
4 met testGroupMoveOneNotificationAndNotMoved; 5 met testGroupMovePeerBackingOffIsUnchecked; 6 met testSeatChangeNotifiesOnce;
7 met testEarlyResetViaIngestLiveRecordsHistory; 8 met testRateLimitedAccountSkippedAndLiveTargetNil; 9 met testLoginLossAndRestoreByFingerprint;
10 met testLegacyProfileRecordsHistoryUnderUuid; 11 met testOldTeamExpiryAndManualDelete; 12 met testProbeOfFollowedOrgSavesClaudeUsageOthersDoNot;
13 met testStopDuringRoundPersistsNothing; 14 met testDisabledStartDoesNothing; 15 met scripts/validate-clt.sh: 560 executed, 558 ok, 0 failed, 2 skipped (pre-existing keychain skips).

## Flow
start() -> loop -> tick(now): syncAccounts (register, migrate) -> repairCurrent -> runDueLists (BoundedTaskRunner) -> runRound (probes -> gathered samples -> apply per account -> forced lists -> detect).
Every result path: baseObservation -> apply (AccountRules.apply) -> process (store, history, events, notifier, current repair); confirmed removals with peers -> runGroupMove.
Loop side: ingestLive / liveTarget / makeCurrent / deleteOldPair / reportRefreshRejected call the same apply+process. stop() bumps generation; stale async results are dropped before any write.

## Tests
TeamTrackerTests (19 tests), command `scripts/validate-clt.sh`: all ok. `git diff --check` clean.

## Edge cases
Handled: profile deleted in flight (apply guards on store lookup), Cloudflare ignored on probes/lists, same org on two accounts, no profiles, disabled, stale generation, OAuth cached reading (lastUpdated <= lastSampleAt).
Not handled: a profile gaining a session key after registration keeps its first hasOrgList flag.

## Shortcuts
- `ponytail:` in syncAccounts: hasOrgList is fixed at first registration; upgrade = unregister/register on credential change.
- Added init params `isEnabled` and `runsLoop` (defaulted) beyond the packet signature, for tests.

## Lessons
- AccountRules sets lastSampleAt from the injected clock, so probe freshness for detection uses lastSampleAt > lastRoundAt, not Date().
- Group-move tests: processing order of a list batch is random (uuid sort); setups must not depend on it.
