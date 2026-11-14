# Troubleshooting

## No usage appears

1. Open **Settings** and check that the profile has credentials: a claude.ai sign-in, or a synced Claude Code login.
2. If the popover says credentials have expired, sign in again under **Settings → Claude.ai**.
3. Check your internet connection, then press refresh in the popover.

On the free plan claude.ai reports no usage limits, and the popover says so.

## 403 "Invalid authorization for organization"

Sign in again under **Settings → Claude.ai** and pick your organization on the second step. This happened when an organization from an earlier sign-in was kept; it is fixed in 3.4.0.

## E3006, "Request blocked by Cloudflare protection"

Update to 3.4.0 or later, then sign in again under **Settings → Claude.ai**.

## The numbers look inverted

**Settings → Appearance → Show Remaining Percentage** switches every percentage from used to remaining. The popover labels each number "used" or "remaining".

## The menu bar icon is missing

- On macOS 26 and later, dragging an icon out of the menu bar turns the app off under **System Settings → Menu Bar**. Turn **Claude Usage** back on there; reinstalling does not reset it.
- On a crowded menu bar, macOS hides icons behind the notch. Quit another menu bar app or use fewer icons (**Settings → Appearance**).

## Claude Code asks me to log in after switching profile

The profile's saved Claude Code login had expired. Run `/login` in Claude Code with that account, then switch to the profile again. See [Profiles](profiles.md).

## Statusline

- **Nothing appears:** restart Claude Code after clicking **Apply**, and check that `~/.claude/settings.json` has a `statusLine` entry.
- **`Usage: ~`:** the statusline could not get a reading. Make sure the app is running and the active profile is signed in to claude.ai.
- **`(stale 13m)`:** the app has not refreshed for that long. Check that it is running.

## Widgets

See [Widgets](widgets.md#if-a-widget-shows-nothing).

## Updates

**Settings → Updates** shows the current version and checks for a new one. If that fails, download the latest release from GitHub and replace the app.

## Still stuck

Open an [issue](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues) with the app version, your macOS version, and any error code the app showed.
