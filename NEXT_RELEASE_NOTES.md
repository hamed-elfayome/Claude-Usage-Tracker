# Next Release Notes — Claude Usage

**Version:** v3.1.2 (build 16)
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
- [x] Bump version (3.1.2) and build (16) in Xcode project
- [x] Build succeeds (macOS); unit tests pass (`** TEST SUCCEEDED **`)
- [ ] Update `CHANGELOG.md` with these notes
- [ ] Verify on a macOS 26 host: crash gone, menu bar item appears, full-screen popover
- [ ] Close the resolved PRs (#220, #221) and issues after shipping `next-release` → `main`
