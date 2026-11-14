# Setup

The app needs one way to read your usage. Any of the three below works; you can add the others later.

## 1. With Claude Code (nothing to configure)

If [Claude Code](https://claude.com/claude-code) is installed and you have run `claude login`, launch the app. It reads that login and starts tracking.

## 2. Sign in to claude.ai

1. Click the menu bar icon, then **Settings**.
2. Open **Claude.ai** in the sidebar.
3. Click **Sign in to Claude.ai** and log in in the window that opens.
4. Pick your organization and confirm.

The session key is read from the sign-in automatically and stored in the Keychain. You need this sign-in for the terminal statusline, even if the app otherwise runs on your Claude Code login.

## 3. Paste a session key

1. Open [claude.ai](https://claude.ai) in a browser and log in.
2. Open the developer tools (`Cmd+Option+I`) and go to **Application** (Chrome, Edge) or **Storage** (Firefox, Safari).
3. Under **Cookies → https://claude.ai**, copy the value of `sessionKey`. It starts with `sk-ant-sid01-`.
4. In the app: **Settings → Claude.ai → Advanced: Manual Session Key**. Paste it, click **Test Connection**, pick your organization, and save.

## API Console billing

To track API spend as well, open **Settings → API Console** and sign in to the Anthropic Console there. The popover then shows monthly cost, a daily chart and a per-key breakdown, and the menu bar can show an API Credits icon.

## Where things are

Settings has a sidebar. The top part belongs to the selected profile; the rest applies to the whole app.

| Section | What you set there |
|---|---|
| Claude.ai, API Console, CLI Account, Codex Account | The profile's credentials |
| Appearance | Menu bar icon style, which metrics get an icon, colors, used or remaining, pace options |
| General | Refresh interval (10 to 300 seconds), auto-start, notifications, terminal launcher |
| History | Charts of past usage, and export |
| Manage Profiles | Create, rename and delete profiles; show one or all in the menu bar; auto-switch |
| Claude CLI | The terminal statusline |
| Dynamic Island, Keep Awake | See [Claude Code](claude-code.md) |
| Popover, Shortcuts, Language, Updates | App-wide preferences |

## Next

- Several accounts: [Profiles](profiles.md)
- Terminal statusline, Dynamic Island, Keep Awake: [Claude Code](claude-code.md)
- Desktop widgets: [Widgets](widgets.md)
