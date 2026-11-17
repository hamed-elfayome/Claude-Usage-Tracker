## Summary
Docs only: a "Team tracking" section in docs/profiles.md (events, Google sign-in, limits),
two troubleshooting entries, and an Unreleased block in CHANGELOG.md.
No code changed.
## Changes
- docs/profiles.md: new section "Team tracking (several accounts and teams)" with Events, Signing in with Google, Limits.
- docs/troubleshooting.md: "It says Log in again" and "The wrong account is shown", before Statusline.
- CHANGELOG.md: new "## [Unreleased]" above 3.4.0 with Added (Team tracking) and Changed (reset shift, 404) bullets.
## Acceptance
1. met: 8 events listed under "### Events".
2. met: 5-minute check, 15-day deletion, Settings → Profiles in the section.
3. met: both fallbacks (browser session key, Claude Code login) and the TBD (owner) line.
4. met: "Two changes between checks show as one."
5. met: both headings in troubleshooting.md.
6. met: Added and Changed under [Unreleased].
7. met: git status shows only 3 .md files; validate-clt.sh: 600 tests, 598 ok, 0 failed, 2 skipped.
## Flow
Docs only; troubleshooting "wrong account" links to profiles.md.
## Tests
No new tests (docs). scripts/validate-clt.sh: Executed 600 tests: 598 ok, 0 failed, 2 skipped. git diff --check: clean.
## Edge cases
The owner's Google check result is left as TBD (owner) on purpose.
## Shortcuts
none
## Lessons
none
