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

## Non-goals
- No credential handling by the agent; no automatic account switching; no change to how logins are created.
- Do not rewrite unrelated features (Codex, Console API, widget) beyond what the data-model change forces.

## Quality bar
Production-grade: unit tests with recorded fixture responses for every event type (switch, move, seat change, early reset, 429, login loss, migration); existing tests stay green; no new third-party dependencies.
