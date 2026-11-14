# Multi-team tracking — requirements (Elephant brief)

Owner's situation: several Claude accounts, company **Team plan**. The team (claude.ai organization)
an account belongs to changes in two ways:
1. **The owner switches** (logs Claude Code / claude.ai into another org they belong to). Both orgs stay in the org list.
2. **The admin moves the seat** to another org (old org disappears from the list, a new one appears),
   or changes the **seat type** (Standard ↔ Premium) inside the same org (limit size changes).

Today each of these looks like "my limits reset". It is not: each (account, org, seat) has its own counters.

## Facts about the current code (verified by reading, file:line)
- Profile stores one `organizationId` (+ `apiOrganizationId`) — `Claude Usage/Shared/Models/Profile.swift:13-84`; secrets in Keychain, rest in UserDefaults (`Shared/Storage/ProfileStore.swift:29-60`).
- Stored org id is used without re-validation (`ClaudeAPIService.swift:480-484`); auto-pick logic `ClaudeAPIService+Types.swift:41-46`; cleared only when session key changes (`ClaudeAPIService.swift:258-262`). No org-list change detection.
- OAuth path `https://api.anthropic.com/api/oauth/usage` (`ClaudeAPIService.swift:546`) uses the token's org implicitly; fallback reads rate-limit headers (`:627-640`). `oauthAccountJSON` exists on Profile.
- Claude Code credentials: Keychain + `~/.claude/.credentials.json`, per-profile CLAUDE_CONFIG_DIR, token refresh (`ClaudeCodeSyncService.swift:75-145, 940-1100`).
- Reset detection only when `resets_at` shifts > 5 min (`Models/UsageHistory.swift:326-335`, `MenuBarManager.swift:1512-1552`). History per profile `usageHistory_<uuid>.json` (`UsageHistoryService.swift`).
- Polling 30 s per profile, profiles fetched sequentially (`Constants.swift:152`, `MenuBarManager.swift:1039`).
- Xcode project, XCTest target `Claude UsageTests/` (~390 tests), macOS 13 app / 14 widget.

## Required behaviour
R1. Track every **(account, org)** pair the account belongs to, not one org per profile. Each pair has its own 5-hour, weekly (and per-model) usage, reset times and history.
R2. **Org-list refresh**: re-read `/api/organizations` every 15 min and immediately after a 401/403/404 on a usage call. Never keep polling an org the account no longer belongs to.
R3. **Owner switch**: detect which org the Claude Code login currently belongs to (from oauth account data / token) and mark it "active". Both orgs keep being tracked. Event: "Now using team B".
R4. **Admin move**: saved org gone + new org present → event "Moved by admin: A → B"; the account follows B automatically; A's history kept read-only.
R5. **Seat-type change**: same org, plan/tier details change (or limit capacity changes) → event "Seat changed", new usage baseline. If no API field reveals the tier, fall back to "limit size changed" detection and document the limitation.
R6. **Real early reset**: same org + same seat, usage drops sharply while `resets_at` is unchanged (or moves) → event "Early reset" + notification. Org switches/moves/seat changes must never be reported as resets. Threshold must keep false alarms rare; justify it.
R7. **Polling**: active org every 30 s, idle orgs every 5 min, accounts/orgs fetched concurrently with a cap (e.g. 4), exponential backoff on 429. Budget: N accounts × M orgs must not cause rate limiting.
R8. **Login loss**: if a move invalidates the Claude Code login, show "Log in again" for that account instead of stale numbers.
R9. **"Most room left" view**: one list of all (account, org) pairs sorted by remaining 5-hour and weekly headroom.
R10. **Migration**: existing profiles upgrade without data loss (current org becomes first tracked org; existing history attached to it).
R11. Known limit to document: two changes within one polling interval collapse into the final state.

Owner note (14 Nov 2026): the owner mainly uses the **Claude desktop app**, whose active org is stored in its
encrypted storage and must not be read. So R3's "active" marker only exists for Claude Code logins; for desktop-app
use, all orgs are tracked and an owner switch shows up only as usage moving between orgs (no "Now using" event).

R12. **Old teams** (an org the account no longer belongs to, e.g. after an admin move): the owner can delete one
by hand (confirm dialog), and it is deleted automatically **15 days after it was last seen** in the org list.
If the org reappears before then, it becomes current again with its history intact. Orgs the account still
belongs to are never auto-deleted, however idle. Deleting removes that org's history file and settings only.
R13. **Group moves**: the owner has 5 Google-login accounts, and a team change moves all 5 at once. When one
account detects a move (R4), immediately refresh the org list of every other account that shared the old org,
and report the result as one grouped event ("5 accounts moved: A → B"), not 5 notifications. Accounts that did
not move are listed in that event.
R14. **Google sign-in**: all accounts sign in with Google. Check whether the app's in-app claude.ai sign-in works
with Google (Google often blocks embedded web views); if it does not, the spec must say which existing path works
(pasted session key, or the Claude Code login, which uses the system browser) and the UI must point there.

## Owner revision (14 Nov 2026) — OVERRIDES R1, R3, R7, R9 where they conflict
Model: **follow the account the owner is using**, not live tracking of everything.
- R15. Exactly one (account, org) pair is **current**; it is polled live (30 s). Every other pair is **saved**:
  its last reading and reset times are kept, it is not polled at the 30 s rate.
- R16. **Detect current from usage**: every signed-in account is probed lightly every 5 min. The pair whose
  5-hour usage rose since the previous probe becomes current (if several rose, the largest rise wins; ties keep
  the existing current). The old current becomes saved with its last reading. Event: "Now on account B (team X)".
  A manual "Make current" menu item overrides detection until usage rises on another account.
- R17. **Saved projection**: when a saved pair's `resets_at` passes, show that window as reset (0%, next reset
  unknown until the next probe) instead of stale numbers; mark it "projected". The next probe replaces it.
- R18. Budget: 5 accounts × 1-2 orgs at 5-min probes + 1 current at 30 s; concurrency cap and 429 backoff from R7 still apply.
- R2, R4, R5, R6, R8, R10, R11, R12, R13, R14 still apply. R13 grouped move detection runs on the probes.
- Known limit: a switch is noticed only after the first message on the new account, up to 5 min late.
- "Most room left" (R9) becomes optional; keep it only if it is a thin view over saved/current data.

## Non-goals
- No account switcher in the app (owner declined it).
- No credential handling by the agent; no automatic account switching; no change to how logins are created.
- Do not rewrite unrelated features (Codex, Console API, widget) beyond what the data-model change forces.

## Quality bar
Production-grade: unit tests with recorded fixture responses for every event type (switch, move, seat change, early reset, 429, login loss, migration); existing tests stay green; no new third-party dependencies.
