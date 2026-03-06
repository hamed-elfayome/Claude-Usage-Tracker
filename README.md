# Claude Usage Tracker — Chrome Extension

> **Forked from** [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) (macOS app) — this fork adds a cross-platform Chrome extension.

<div align="center">

  **Real-time Claude AI usage monitoring directly in your browser toolbar**

  ![Chrome](https://img.shields.io/badge/Chrome-Extension-yellow?style=flat-square&logo=googlechrome)
  ![Manifest](https://img.shields.io/badge/Manifest-v3-blue?style=flat-square)
  ![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
  ![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)
  ![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey?style=flat-square)

  <sub>Works on any OS that runs Chrome — no installation beyond the extension itself</sub>

</div>

---

## Overview

Claude Usage Tracker is an open-source Chrome extension that gives Claude AI users real-time visibility into their usage limits directly from the browser toolbar.

Inspired by the [macOS Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker), this extension reimplements its core functionality as a cross-platform, zero-configuration browser extension accessible on **Windows, macOS, and Linux**.

### Key features

- **Zero-config** — automatically reads your `sessionKey` cookie when you're logged into [claude.ai](https://claude.ai). No manual setup needed.
- **Toolbar badge** — live usage % with green / orange / red color coding updated in the background
- **Popup UI** — session (5-hour window), weekly, and Opus usage cards with progress bars and reset countdowns
- **Desktop notifications** — alerts at 75 %, 90 %, and 95 % thresholds, firing once per reset window
- **Multi-profile** — manage multiple Claude accounts, each with an independent session key and settings
- **Settings page** — badge display, percentage mode, refresh interval, notification thresholds

---

## Installation

### From source (Developer Mode)

1. Clone this repository:
   ```bash
   git clone https://github.com/Ali-Aldahmani/claude-usage-extension.git
   ```
2. Open **chrome://extensions** in Chrome
3. Enable **Developer mode** (toggle in the top-right corner)
4. Click **Load unpacked** and select the `chrome-extension/` folder inside the cloned repo

That's it. As long as you are logged into [claude.ai](https://claude.ai) in Chrome, the extension works immediately with no further configuration.

> Chrome Web Store release is planned for a future version.

---

## How it works

| Step | What happens |
|------|-------------|
| 1 | Extension reads your `sessionKey` cookie from `claude.ai` (requires the `cookies` permission) |
| 2 | Background service worker calls `GET https://claude.ai/api/organizations/{org_id}/usage` |
| 3 | Usage data is cached in `chrome.storage.local` and the toolbar badge is updated |
| 4 | Popup reads from the cache — opens instantly without an extra network request |
| 5 | Alarm fires every 1–5 minutes (configurable) to refresh in the background |

---

## Manual session key (optional)

If cookie auto-detection ever fails:

1. Open the extension popup → **Settings** (gear icon)
2. Go to **Profiles → Edit**
3. Paste your session key (found in Chrome DevTools → Application → Cookies → `claude.ai` → `sessionKey`)

---

## Multi-profile support

Each profile stores its own:

- Session key (or relies on the auto-detected cookie)
- Cached organization ID
- Independent settings (refresh interval, badge display, notifications)

Switch profiles from the dropdown in the popup header. Create and manage profiles in **Settings → Profiles**.

---

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Badge display | Session % / Weekly % / Off | Session % |
| Percentage mode | Used / Remaining | Used |
| Refresh interval | 1 min / 2 min / 5 min | 1 min |
| Session notifications | 75 % / 90 % / 95 % | All on |
| Weekly notifications | 75 % / 90 % / 95 % | All on |

---

## Project structure

```
chrome-extension/
├── manifest.json          Extension config (Manifest v3)
├── background.js          Service worker — polling, badge, notifications
├── storage.js             Profile & settings persistence
├── api.js                 Claude.ai API integration
├── popup.html / css / js  Toolbar popup UI
├── settings.html/css/js   Full settings page
├── icons/                 16 / 32 / 48 / 128 px PNG icons
└── scripts/
    └── generate_icons.py  Regenerate icons (stdlib only, no dependencies)
```

### Rebuild icons

```bash
python chrome-extension/scripts/generate_icons.py
```

---

## API reference

**Usage endpoint**
```
GET https://claude.ai/api/organizations/{org_id}/usage
Cookie: sessionKey=<value>
```

**Response fields used**

| Field | Description |
|-------|-------------|
| `five_hour.utilization` | Session usage % (0–100) |
| `five_hour.resets_at` | ISO 8601 timestamp of next session reset |
| `seven_day.utilization` | Weekly usage % across all models |
| `seven_day.resets_at` | ISO 8601 timestamp of weekly reset |
| `seven_day_opus.utilization` | Opus-specific weekly usage % (Pro only) |

---

## Contributing

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'feat: describe your change'`
4. Push and open a Pull Request

---

## Acknowledgments

This is a fork of [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker), a native macOS menu bar app. The original macOS app source is still present in this repo. This fork extends it by adding a Chrome extension that brings the same functionality to all platforms.

---

## Disclaimer

This extension is not affiliated with, endorsed by, or sponsored by Anthropic PBC. Claude is a trademark of Anthropic PBC. This is an independent, open-source tool for personal usage monitoring.

## License

MIT — see [LICENSE](LICENSE)

---

<div align="center">
  <sub>Built for the Claude AI community</sub>
</div>
