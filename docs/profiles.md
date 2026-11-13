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
