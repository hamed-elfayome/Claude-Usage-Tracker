# Profiles

A profile is one account: its credentials, its appearance, its notifications and its usage history. You can have as many as you like.

## Create and switch

1. **Settings → Manage Profiles → Create New Profile.** It gets a generated name you can change.
2. Select the profile in the sidebar and add credentials under **Claude.ai**, **API Console**, **CLI Account** or **Codex Account**.
3. Switch from the popover's dropdown or the sidebar.

Each profile keeps its own icon style, refresh interval, auto-start setting and notification thresholds.

## One profile or all of them in the menu bar

**Manage Profiles → Show Multiple Profiles** puts every selected profile in the menu bar at once. Click a profile's icon to open its numbers. With it off, only the active profile is shown.

In this mode you choose one compact style for all profiles (rings, bar, percentage or dot), and each profile refreshes on its own credentials.

## Claude Code follows the active profile

Under **CLI Account**, **Sync from Claude Code** copies the login Claude Code is using into the profile. From then on, switching to that profile switches Claude Code's login too.

If a profile's saved login can no longer be refreshed, the switch is cancelled and your current login is left alone, so running Claude Code sessions are not logged out. Run `/login` in Claude Code with that account and switch again.

## Auto-switch

**Manage Profiles → Auto-Switch Profile** moves to the next profile with room when the active one reaches its session limit.

## Terminal launchers

To run different Claude Code accounts side by side:

1. On the profile, **Settings → General → Install Launcher**.
2. Run `claude-<profile>` in a terminal. It opens Claude Code with that profile's own config directory; sign in once with `/login`.
3. The app notices the new login and links it to the profile. Usage tracking follows that account from then on.

Plain `claude` keeps following the active profile, with one exception. Switching to a profile that has its own launcher login leaves plain `claude` signed in as it was: copying that login across would put one sign-in in two places, and whichever Claude Code refreshed it second would be logged out. Use the profile's `claude-<profile>` command for that account.

Removing a launcher never deletes its login.

## OpenAI Codex profiles

When you create a profile, choose **OpenAI Codex** as its provider to track Codex limits in the same menu bar.

- It reads your existing `~/.codex/auth.json`, or credentials you paste under **Codex Account**.
- Codex's 5-hour and weekly windows appear as the session and weekly rows.
- Codex Pro has no 5-hour limit, so those profiles show the week only.
- Claude-only features (statusline, auto-start, Dynamic Island) are hidden for Codex profiles.

Adding another provider is documented in [ADDING_A_PROVIDER.md](ADDING_A_PROVIDER.md).

## Team tracking (several accounts and teams)

Team tracking follows the account you are using and the teams each account belongs to.

**Turn it on:** **Settings → Profiles**, then switch on Team tracking.

**How it finds the account in use.** Every 5 minutes the app checks which account's 5-hour usage went up. That account becomes the current one and is shown in the menu bar. The app never switches any login to do this. If it picks the wrong one, open the Teams list and click **Make current**.

**Other teams.** The other teams are checked every 5 minutes too. After a team's reset time passes, its numbers show as "projected" until the next check. A team that disappears is deleted 15 days later. You can also delete it by hand.

### Events

- **Now on account (team):** you started using another account or team, and it is now the current one.
- **Moved by admin:** an admin moved your account to another team.
- **N accounts moved:** several of your accounts were moved to another team at the same time.
- **Removed from team:** an account no longer belongs to a team it was in.
- **Team changed:** the account is now in a different team, but the app cannot tell whether you switched or were moved.
- **Seat changed / Limit size changed:** the account's seat type or usage limit got bigger or smaller.
- **Early reset:** the usage went back to zero before the reset time.
- **Log in again:** the saved login for this account stopped working. Sign in again.

### Signing in with Google

Google may block the in-app sign-in window. If it does, use one of these instead:

- Sign in at claude.ai in your browser, copy the session key and paste it into the app.
- Use the Claude Code login. This shows only one team.

In the Google window, pick the Google account you want to track.

Checked by the owner on TBD (owner): in-app Google sign-in TBD (owner) (works / is blocked).

### Limits

- A switch is seen only after your first message on the new account, so it can show up to 5 minutes late.
- Using two accounts at once (for example the desktop app on one and Claude Code on another) flips the current account back and forth.
- Any use of an account counts, including another device or a teammate on a shared login.
- Two changes between checks show as one.
- The app uses Claude endpoints that are not documented. They may change. If they do, events stop showing instead of showing wrong ones.
- A seat change without a tier field may show as an early reset.
- Accounts that only use the Claude Code (OAuth) login see one team.
- When the Claude Code profile is not the current one, its statusline refreshes every 5 minutes.

**Please help:** capture a redacted `/api/organizations` response for each seat type (**Settings → Debug network log**) and send it to us. Remove names, emails and IDs first.
