### MT-9 — User docs and changelog for Team tracking

Size: S
Risk: normal
Importance: low
After: MT-7

**Goal:** Tell users what Team tracking does, how it decides the account in use, what each event means, how to
sign in with Google, and its limits. Spec `docs/specs/multi-team-tracking.md` §4, §6, §8, §11, §15.

**Files**
- `docs/profiles.md` (add a section; keep existing ones)
- `docs/troubleshooting.md` (two entries)
- `CHANGELOG.md` (under the top "Unreleased" heading; create it above the newest release if missing)

**Steps**
1. `docs/profiles.md`, new section "Team tracking (several accounts and teams)": how to turn it on (Settings →
   Profiles); the current account is detected from rising 5-hour usage, checked every 5 minutes, shown in the menu
   bar without switching any login; "Make current" in the Teams list; other teams are checked every 5 minutes and
   show "projected" after their reset time; old teams are deleted 15 days after they disappear (or by hand).
   Events, one plain sentence each: Now on account (team); Moved by admin; N accounts moved; Removed from team;
   Team changed; Seat changed / Limit size changed; Early reset; Log in again.
2. Same section, "Signing in with Google": the in-app sign-in may be blocked by Google; then sign in at claude.ai in
   your browser and paste the session key, or use the Claude Code login (one team only). Pick the right Google
   account in the Google window. Leave a line "Checked by the owner on <date>: in-app Google sign-in works / is blocked"
   with the date and result as `TBD (owner)`.
3. Limits subsection in plain words: the spec §15 bullets (switch seen up to 5 min late; using two accounts at once
   flips the current one; two changes between checks show as one; undocumented endpoints; seat change without a tier
   field may show as early reset; OAuth-only accounts see one team; statusline refreshes every 5 min when the Claude
   Code profile is not current). Include the request to capture a redacted `/api/organizations` response per seat
   type (Settings → Debug network log).
4. `docs/troubleshooting.md`: "It says Log in again" (re-sign in to claude.ai in Settings or run `claude /login`
   for that account; the app never logs in for you) and "The wrong account is shown" (use "Make current"; detection
   needs the first message on the new account).
5. `CHANGELOG.md`: "Added" bullet (Team tracking: follows the account in use, team events, Teams list) and
   "Changed" bullets (a shifted reset time without a usage drop is no longer recorded as a reset; HTTP 404 maps to
   "not found").
6. Plain English, short sentences. Validate.

**Acceptance criteria**
1. `docs/profiles.md` has the "Team tracking" section with all 8 events.
2. It states the 5-minute check, the 15-day old-team deletion and how to turn the feature on.
3. The Google sign-in paragraph names both fallbacks and has the `TBD (owner)` line.
4. The limits list contains the "two changes between checks show as one" sentence.
5. `docs/troubleshooting.md` has both entries.
6. `CHANGELOG.md` has the Added and Changed bullets under Unreleased.
7. No code file changed; full suite still passes.

**Tests:** none beyond the suite (docs only). Check links with `grep -n "](" docs/profiles.md` by eye.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
