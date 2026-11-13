<div align="center">
  <a href="mailto:hamedelfayome@gmail.com?subject=Claude%20Usage%20Tracker%20%E2%80%94%20Sponsorship"><img src="https://claudetracker.com/asset/sponsor.svg" alt="Sponsor slot available — get in touch: hamedelfayome@gmail.com" height="44"></a>
</div>

<br>

<div align="center">
  <a href="https://claudetracker.com/#fleet"><img src="https://claudetracker.com/map.svg" alt="Claude Usage Tracker — a native macOS menu bar app for real-time monitoring of Claude AI usage limits. Live worldwide distribution map." width="100%"></a>

  <a href="https://claudetracker.com"><img src="https://claudetracker.com/asset/languages.svg?list=English%2CEspa%C3%B1ol%2CFran%C3%A7ais%2CDeutsch%2CItaliano%2CPortugu%C3%AAs%2CPortugu%C3%AAs%20(BR)%2C%E6%97%A5%E6%9C%AC%E8%AA%9E%2C%ED%95%9C%EA%B5%AD%EC%96%B4%2C%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87%2C%E7%B9%81%E9%AB%94%E4%B8%AD%E6%96%87%2CT%C3%BCrk%C3%A7e%2C%D0%A3%D0%BA%D1%80%D0%B0%D1%97%D0%BD%D1%81%D1%8C%D0%BA%D0%B0%2CTi%E1%BA%BFng%20Vi%E1%BB%87t%2C%D9%81%D8%A7%D8%B1%D8%B3%DB%8C" alt="Localized in 15 languages" width="100%"></a>

  <br>

  <a href="https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip"><img src="https://claudetracker.com/asset/download.svg" alt="Download for macOS — latest release, ~6 MB, signed &amp; notarized" height="78"></a>

  <br>

  <a href="https://www.buymeacoffee.com/hamedelfayome"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="54"></a>

  <img src="https://claudetracker.com/asset/specs.svg?items=macOS%2013.0%2B%20(Ventura)%2C~6%20MB%2CNative%20Swift%20%2F%20SwiftUI%2COfficially%20Signed" alt="macOS 13.0+ (Ventura) · ~6 MB · Native Swift/SwiftUI · Officially Signed" height="40" align="middle"> 
  <a href="https://claudetracker.com"><img src="https://claudetracker.com/asset/website.svg" alt="claudetracker.com — live stats &amp; install" height="30" hspace="4" align="middle"></a>

</div>

---

**Claude Usage Tracker** is a native macOS menu bar app that shows how much of your Claude limits you have used, and when they reset. It tracks the 5-hour session, the weekly limit, per-model limits and API spend, for as many accounts as you have, and it can do the same for OpenAI Codex.

<div align="center">
  <img src=".github/settings.gif" alt="A walkthrough of the settings window" width="600">
  <img src=".github/icon.jpg" alt="Menu bar icon" height="180">
  <img src=".github/popover.png" alt="Usage popover" width="200">
</div>

## Install

**Homebrew** (recommended)

```bash
brew install --cask hamed-elfayome/claude-usage/claude-usage-tracker
```

**Direct download:** get [Claude-Usage.zip](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip), unzip it, and drag `Claude Usage.app` to Applications.

**Nix:** `nix-shell -p claude-usage-tracker`, or add `claude-usage-tracker` to `home.packages`.

**From source:** clone the repository, open `Claude Usage.xcodeproj` in Xcode, and run.

The app is signed and notarized, needs macOS 13 (Ventura) or later, and updates itself (Settings → Updates). Desktop widgets need macOS 14.

## Get started

Pick whichever fits how you use Claude:

| You have | Do this |
|---|---|
| [Claude Code](https://claude.com/claude-code), logged in | Launch the app. It finds the login on its own. |
| A claude.ai account | Settings → Claude.ai → **Sign in to Claude.ai**, then pick your organization. |
| A session key you'd rather paste | Settings → Claude.ai → **Advanced: Manual Session Key**. |

Click the menu bar icon to see your usage. The [setup guide](docs/setup.md) covers each path step by step, including API Console billing.

The terminal statusline needs a claude.ai sign-in even if the app itself runs on your Claude Code login.

## What it does

**Tracks your limits**
- The 5-hour session, the weekly limit, and per-model weekly limits (Fable, Opus, Sonnet, Design)
- Extra usage and, on Enterprise plans, your own month-to-date spend
- API Console spend, with a daily chart and a per-key breakdown
- Plans without a 5-hour limit (Claude Ultra, Codex Pro) show the week as the main number
- History charts for session, weekly and billing data

**Shows it where you look**
- Menu bar icon in five styles, with separate icons per metric if you want them
- A time marker on every bar: how far through the window you are, colored by projected pace
- Popover with every limit, reset times and Claude's service status
- Six desktop widgets, small to extra large, each with a profile picker
- Used or remaining percentages, three color modes, 15 languages

**Handles several accounts**
- Unlimited profiles, each with its own credentials, appearance and notifications
- Show every profile in the menu bar at once, or only the active one
- OpenAI Codex profiles alongside Claude ones
- Switching profile switches your Claude Code login with it
- `claude-<profile>` terminal commands that always open a given account

**Works with Claude Code**
- A terminal statusline: directory, branch, model, context, usage, pace, reset time, prompt-cache hit rate
- Dynamic Island (beta): what Claude Code is doing, at the notch
- Keep Awake: stops the Mac sleeping while Claude Code works

**Looks after itself**
- Notifications at 75%, 90%, 95% and thresholds you add
- Auto-start a new session when the last one resets
- Auto-switch to the next profile when one hits its session limit
- Global keyboard shortcuts, launch at login, headless Macs supported

## Guides

| Guide | What's in it |
|---|---|
| [Setup](docs/setup.md) | Signing in three ways, API Console billing, where settings live |
| [Profiles](docs/profiles.md) | Multiple accounts, Codex profiles, terminal launchers |
| [Claude Code](docs/claude-code.md) | Statusline setup and components, Dynamic Island, Keep Awake |
| [Widgets](docs/widgets.md) | The six desktop widgets and how to pick a profile |
| [Troubleshooting](docs/troubleshooting.md) | Sign-in errors, missing icon, statusline problems |
| [Adding a provider](docs/ADDING_A_PROVIDER.md) | For contributors: how providers plug in |

## What's new

- **v3.4.0 (2026-11-13)**: **Desktop widgets** — six WidgetKit widgets in small to extra-large sizes with a per-widget profile picker; **Keep Awake** — keeps the Mac awake while Claude Code works; **macOS 13 (Ventura) support**; optional **Fable weekly** metric in the menu bar and statusline (#318, #323); **exclude weekends from weekly pace** (#326); **monthly spend for Enterprise members** (#287); prompt-cache hit rate in the statusline; plans without a 5-hour limit (Claude Ultra, Codex Pro) show weekly as the primary metric (#356); profile switching no longer logs Claude Code out on a dead saved login (#331) and pinned profiles keep their login to themselves (#355); usage history no longer grows without bound (#337); E3006 and 403 sign-in failures fixed (#319, #266); auto-start respects the weekly limit and backs off after failures (#334); macOS 26 material crash fixed (#333); statusline no longer blanks on an old cache (#322); popover percentages say "used" or "remaining" (#269); Persian localization — 15 languages total. Thanks to 15 community contributors.

- **v3.3.0 (2026-08-29)**: **Multi-provider architecture with OpenAI Codex support** (#229) — per-profile provider selection on a registry pattern (`docs/ADDING_A_PROVIDER.md`); **per-profile terminal launchers** — `claude-<profile>` commands with isolated `CLAUDE_CONFIG_DIR` logins and automatic usage tracking after one `/login`; keychain migration finally works on shipped Developer ID builds (#292); popover shows over full-screen apps (#298); Dynamic Island targets the built-in notch (#294); Cloudflare challenges no longer masquerade as expired credentials (#277); macOS 26 multi-profile crash fixes; transient E1000 on profile switch eliminated; obsolete peak-hours indicator removed (#308); Vietnamese localization — 14 languages total. Thanks to 8 community contributors.

Earlier releases are in the [changelog](CHANGELOG.md).

## Privacy and security

- Credentials are stored in the macOS Keychain, never in plain files.
- Usage data stays on your Mac. There is no account and no cloud sync.
- The app talks to claude.ai and Anthropic's API for your usage, over HTTPS only.
- It sends one anonymous heartbeat a day containing the app version, and nothing else.
- The sponsor placement in Settings reads a small JSON file from claudetracker.com, at most every 6 hours, with no cookies or identifiers.
- Updates are delivered over HTTPS and verified by signature.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Contributing

Pull requests are welcome. For a larger change, open an issue first so we can agree on the approach. [CONTRIBUTING.md](CONTRIBUTING.md) has the setup, the localization requirement and the conventions.

<img src="https://contrib.rocks/image?repo=hamed-elfayome/Claude-Usage-Tracker" alt="Contributors" height="30px" />

### Special Thanks

A huge thank you to everyone who contributed code, translations, bug reports, and pull requests. Your effort makes this project possible:

<a href="https://github.com/novastate"><img src="https://github.com/novastate.png" width="40" height="40" alt="novastate" title="novastate"></a>
<a href="https://github.com/heathdutton"><img src="https://github.com/heathdutton.png" width="40" height="40" alt="heathdutton" title="heathdutton"></a>
<a href="https://github.com/tsvikas"><img src="https://github.com/tsvikas.png" width="40" height="40" alt="tsvikas" title="tsvikas"></a>
<a href="https://github.com/kynoptic"><img src="https://github.com/kynoptic.png" width="40" height="40" alt="kynoptic" title="kynoptic"></a>
<a href="https://github.com/bezlant"><img src="https://github.com/bezlant.png" width="40" height="40" alt="bezlant" title="bezlant"></a>
<a href="https://github.com/trickart"><img src="https://github.com/trickart.png" width="40" height="40" alt="trickart" title="trickart"></a>
<a href="https://github.com/Ali-Aldahmani"><img src="https://github.com/Ali-Aldahmani.png" width="40" height="40" alt="Ali-Aldahmani" title="Ali-Aldahmani"></a>
<a href="https://github.com/cuvitx"><img src="https://github.com/cuvitx.png" width="40" height="40" alt="cuvitx" title="cuvitx"></a>

## License

MIT. See [LICENSE](LICENSE).

This application is not affiliated with, endorsed by, or sponsored by Anthropic PBC. Claude is a trademark of Anthropic PBC. This is an independent third-party tool created for personal usage monitoring.

This project is developed with AI-assisted workflows, primarily Claude Code.

---

<div align="center">
  <sub>Built for the Claude AI community</sub>
</div>
