### MT-8 — User docs and changelog for multi-team tracking

Size: S
Risk: normal
Importance: low
After: MT-6, MT-7

**Goal:** Tell users what the feature does, what each event means, and its limits. Spec:
`docs/specs/multi-team-tracking.md` §5, §8, §12.

**Files**
- `docs/profiles.md` (add a section; keep the existing ones)
- `CHANGELOG.md` (add under the top "Unreleased" heading; create that heading above the newest release if missing)
- `docs/troubleshooting.md` (one entry)

**Steps**
1. `docs/profiles.md`: new section "Several teams per account" — what is tracked (every team the account
   belongs to; the Claude Code login's team is "active"), the event list (Now using team B; Moved by
   admin; Team changed; Removed from team; Seat changed / Limit size changed; Early reset; Log in again)
   with one plain sentence each, the "Teams — most room left" list and its sort order, polling rates
   (active 30 s, other teams 5 min, team list 15 min).
2. Limits subsection: copy the five bullets of spec §12 in plain words (two changes between polls show
   as one; undocumented endpoints; OAuth-only accounts see one team; seat change without a tier field
   may show as early reset; early reset shows one poll late). Include the request to capture a redacted
   `/api/organizations` response per seat type via Settings → Debug network log.
3. `docs/troubleshooting.md`: entry "It says Log in again" — run `claude /login` (or re-sign-in to
   claude.ai in Settings) for that account; the app never logs in for you.
4. `CHANGELOG.md`: one "Added" bullet (multi-team tracking, events, most-room-left list) and one "Changed"
   bullet (a shifted reset time without a usage drop is no longer recorded as a reset; 404 maps to "not found").
5. Plain English, short sentences, no marketing words. Validate.

**Acceptance criteria**
1. `docs/profiles.md` contains a "Several teams per account" section listing all 7 user-visible events.
2. The section lists the three polling intervals and the sort rule.
3. The limits subsection contains the R11 sentence about two changes between polls.
4. `docs/troubleshooting.md` has the "Log in again" entry.
5. `CHANGELOG.md` has the Added and Changed bullets under Unreleased.
6. No code file changed; full suite still passes.

**Tests:** none beyond the suite (docs only). Check links with `grep -n "](" docs/profiles.md` by eye.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
