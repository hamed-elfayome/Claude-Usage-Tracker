## Verdict
PASS. The tracker wiring sits in the right layers (pure static plan helpers in MenuBarManager, a notifier adapter in NotificationManager, a handler in the provider), every new branch is guarded by `isRunning` or the provider, and the design can meet all 11 acceptance criteria.

## Must fix
(none)

## Notes
- Data flow matches the TeamTracker contract. `liveTarget()` needs `authState == .ok`, so a `needsLogin` account always goes down `.skip`, and `applyTeamLoginState()` runs there too, which covers AC9. `ingestLive` drops cached readings itself.
- Single mode marks a reading as cached when `profile.claudeUsage == newUsage`. This works because `ClaudeUsage.lastUpdated` is part of the synthesized Equatable: a fresh fetch never compares equal, and a cached fallback does. Multi mode already used this rule.
- The single and multi catch paths pass the raw `error` to `ingestLive`, and `ingestLive` keeps only `AppError`. The usage chain also throws `APIError`, which `AppError.wrap` would turn into `.unknown` anyway, so membership handling loses nothing. Passing `appError` in single mode would still be slightly tidier. This is not a defect.
- In the tracker-owned single path, a failure on a current account that is not active still sets `hasCredentialError` and `lastRefreshError` for the shown account. That matches the "banner follows the shown account" design.
- API console usage (`apiUsage`) and the reset checks for billing cycles still follow the active profile. That is out of scope and correct, because console billing is per active profile.
- The UserDefaults observer fires on every defaults write. The handler is cheap: it compares against `teamTrackingWasEnabled` and returns early. Acceptable.
- The popover's `teamRows` is recomputed on every body pass. It is pure, with no keychain access (`StoredCredentialReader.hasCredential` reads only profile fields). Acceptable.
- The credential-banner change in the popover, which is outside the named lines, is justified: `lastRefreshError` is a String the banner never showed, so a published `teamLoginMessage` is the right seam.
- The gap the builder accepted: while running with `global.current == nil`, single mode makes no live fetch for the active anthropic profile. This is what AC3 and the spec require, and the probe rounds plus `onSample` cover the display.
