# Next Release Notes — Claude Usage

**Version:** v3.2.0 (build 17)
**Branch:** `next-release`
**Base:** `main` (v3.1.1, build 15)

---

## New Features

### Claude Design Weekly Usage Tracking (PR #221)
- Parse `seven_day_omelette` API field for Claude Design usage data
- Display a **Design** usage row in the popover after Session Usage (hidden when 0)
- New fields on `ClaudeUsage`: `designWeeklyTokensUsed`, `designWeeklyPercentage`, `designWeeklyResetTime`
- Localized `menubar.design_usage` across all 13 supported locales

### Close Settings Window with Cmd+W (#223, #252)
- The borderless settings window now closes on **Cmd+W** via a `keyDown` handler on
  `BorderlessSettingsWindow`. `close()` still fires `windowWillClose`, so dock-icon cleanup runs.

---

## Bug Fixes

### macOS 26 Crash in Menu Bar Icon Refresh (PR #221 → #231)
- **Root cause:** `NSImage.tiffRepresentation` crashes inside `SetupTIFFErrorHandler`'s
  `dispatch_once` on the macOS 26 SDK. It was only used to compute an image-equality hash.
- **Fix:** hash via `image.cgImage(...).dataProvider?.data` instead — functionally equivalent,
  no behavior change, no regression on macOS 14/15.
- **Files:** `StatusBarUIManager.swift`

### Menu Bar Item Disappears After Cmd-Drag-Out (PR #251, fixes #222; likely #255/#244)
- **Root cause:** `NSStatusItem` persists `isVisible` keyed by `autosaveName`; cmd-dragging an
  item out writes `false`, so it silently never reappears on next launch.
- **Fix:** set `statusItem.isVisible = true` at all 8 status-item creation sites (position
  persistence via `autosaveName` is unaffected).
- **Files:** `StatusBarUIManager.swift`

### Popover Hidden Behind Full-Screen Apps (PR #257, fixes #256)
- **Root cause:** an inactive `.accessory`/LSUIElement app renders the popover on the desktop
  Space, behind any full-screen window.
- **Fix:** `NSApp.activate(ignoringOtherApps:)` before each `popover.show()`, plus
  `.fullScreenAuxiliary` on the detached popover panel.
- **Files:** `MenuBarManager.swift`

### Menu Bar Color Thresholds Relaxed to 70% / 90% (PR #232, adjusted)
- Anthropic raised plan limits, so the old 50%/80% cutoffs painted the icon yellow/red while
  users still had headroom. New thresholds: **safe <70%, moderate 70–90%, critical ≥90%**
  (used mode + pace projection; remaining mode 30%/10% to match).
- **Files:** `UsageStatusCalculator.swift`, `UsageStatusCalculatorTests.swift`

### CLI Account Switching Fails with 401 "Please run /login" (PR #242 + follow-up; rel. #239)
- **Root cause:** stored OAuth access tokens expire (~8h), but profile switch wrote the stored
  token verbatim — applying a stale token made Claude Code 401. A stale `~/.claude/.credentials.json`
  also shadowed the fresher keychain entry, so re-syncing couldn't recover.
- **Fix:** PR #242 adds per-profile keychain source pin + `refresh_token` grant against
  `platform.claude.com`. Follow-up wires `ensureFreshCredentials()` into the switch path
  (`ProfileManager.activateProfile`) so the token is refreshed and rotated tokens persisted
  before apply; `readSystemCredentials` now prefers a non-expired keychain entry over an expired
  file. **Files:** `ClaudeCodeSyncService.swift`, `ProfileManager.swift`, `MenuBarManager.swift`,
  `Profile.swift`, `CLIAccountView.swift`
- **Contributor:** keychain-pin + refresh by @Taeknology (PR #242).

### CLI Account Switching — Stale Credentials File (carried from prior work)
- `applyProfileCredentials` now also writes `~/.claude/.credentials.json` alongside the Keychain
  so account switching doesn't get shadowed by a stale file. **Files:** `ClaudeCodeSyncService.swift`

### Profile Switching Forced Re-Login — Single-Writer Token Model (fixes #263; supersedes PR #264)
- **Root cause (three compounding bugs):** (1) the app refreshed the *active* profile's OAuth
  tokens from the periodic fetch path, consuming the refresh token Claude Code holds in the
  system keychain; (2) `resyncBeforeSwitching` used the *rotating* `refreshToken` as an
  account-identity check, so same-account rotations were mistaken for a different account and
  never captured; (3) the stale `.credentials.json` mirror shadowed the fresher keychain.
- **Fix:** active profile is never network-refreshed — it is mirrored from the system keychain
  (identity-checked via `oauthAccount.accountUuid`); the resync guard compares account identity
  instead of refresh tokens; credential reads prefer the fresher source (later `expiresAt`,
  tie → keychain). **Files:** `ClaudeCodeSyncService.swift`, `ProfileManager.swift`
- **Credit:** @AlvaroTena independently diagnosed the identity-guard bug with a controlled A/B
  rotation experiment (#263) and submitted the equivalent guard fix (PR #264).

### Usage History Exceeded the 4 MB UserDefaults Limit (fixes #260)
- Per-profile history blobs pushed the CFPreferences domain past the 4 MB hard limit, silently
  dropping ALL preference writes — including profile/credential saves. History now lives in
  per-profile JSON files under Application Support, with a one-time migration that removes the
  oversized keys. **Files:** `UsageHistoryService.swift`

### Popover Layout-Recursion Crash on macOS 26/27 (PR #265)
- `NSPopover.animates` + `.preferredContentSize` sizing fed an unbounded layout loop
  (`windowDidLayout → setFrame → layout`) that overflowed the main-thread stack. Native
  animation disabled; replaced with a SwiftUI fade/scale entrance; plus a 0.25s debounce fixing
  the click-bounces-popover-back-open race. **Files:** `MenuBarManager.swift`,
  `PopoverContentView.swift` — thanks @Leewallace017

### Tracker Went Dormant After Sleep (fixes #268)
- When the active account's token expired during inactivity, the menu bar fell back to the
  default logo until a manual re-sync. An expired system token means the CLI is idle, so the
  tracker now performs the refresh grant once and writes the rotated tokens back to the system
  keychain + mirror file — the CLI seamlessly picks up the new lineage.
  **Files:** `ClaudeCodeSyncService.swift`

### Security: Statusline Scripts No Longer World-Readable (#267, GHSA-mfxh-xpwm-23c7 part 2)
- Generated statusline scripts embed the raw session key and were written `0755`; now `0700`.
  (Part 1 — plaintext profile credentials in UserDefaults — is tracked as a dedicated
  Keychain-migration pass.) **Files:** `StatuslineService.swift`

### Menu Bar Icon Reverting to Default for CLI-Authenticated Users (PR #220)
- UI gating now uses `hasAnyAvailableCredentials()` (aligned with the network fallback) instead
  of `profile.hasUsageCredentials`. **Files:** `MenuBarManager.swift`, `StatusBarUIManager.swift`

---

## Resolves
- Closes **#222** (icon dragged out, never returns), **#256** (popover over full-screen),
  **#223** + **#252** (Cmd+W). Verify-then-close: **#255**, **#244** (menu bar not showing on
  macOS 26), **#250** (default-logo regression).

## Contributors
- **@hbourget** — macOS 26 crash fix (#231), color thresholds (#232)
- **@mlarocque** — menu bar visibility fix (#251)
- **@ernestjsf** — popover over full-screen apps (#257)
- **@nfarina** — menu bar icon fix for CLI-authenticated users (#220)
- **@47vigen** — Claude Design weekly usage tracking (#221)

---

## Checklist (for release)
- [x] Bump version (3.2.0) and build (17) in Xcode project
- [x] Build succeeds (macOS); unit tests pass (`** TEST SUCCEEDED **`)
- [x] Update `CHANGELOG.md` with these notes
- [ ] Verify on a macOS 26 host: crash gone, menu bar item appears, full-screen popover
- [ ] Close the resolved PRs (#220, #221) and issues after shipping `next-release` → `main`

### PR #271 Selective Port (@yelloduxx) — API modernization
- **Profile wipe on upgrade (CRITICAL, would have shipped in v3.1.2):** tolerant `ClaudeUsage`
  decoding — #221's non-optional fields made v3.1.1 profile data fail decode, wiping all profiles.
- **New `limits[]` usage format:** legacy `seven_day_*` per-model fields are null now; per-model
  usage (incl. **new Fable row**) parses from `limits[]`. Verified live.
- macOS 26 sign-in fixes: cookie-store polling (observer never fires), post-login auto-reload,
  transient-401 retry, Cloudflare-challenge detection + cf cookies on API requests.
- 429 usage probes now parse the unified rate-limit headers instead of failing at max usage.
- Perf: 15s-cached system-credentials availability (was a blocking keychain XPC per repaint).
- Not ported: makeStatusItem() refactor (conflicts with merged #251/#231). Close #271 on release
  with credit; #263/#264 also close on release (equivalent fixes shipped).
