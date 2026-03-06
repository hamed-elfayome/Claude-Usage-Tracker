# Claude Usage Tracker

Native macOS menu bar app (macOS 14.0+ / Sonoma) for real-time Claude AI usage monitoring. Built with Swift 5.0+ and SwiftUI, using Xcode 16+.

## Build & test

```bash
# Build (Debug)
xcodebuild build -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Build (Release)
xcodebuild build -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

CI runs on `macos-15` (Xcode 16 required for `PBXFileSystemSynchronizedRootGroup` format). Code signing is disabled — open source, no Apple Developer certificate.

## Architecture

MVVM pattern. Keep views "dumb" — display only, no business logic.

```
Claude Usage/
├── App/              # Entry point, lifecycle
├── MenuBar/          # Status item, popover UI, MenuBarManager (ViewModel)
├── Views/            # Settings, SetupWizard
└── Shared/
    ├── Models/       # Pure Swift data structs (ClaudeUsage, ClaudeStatus)
    ├── Services/     # API, notifications, statusline (async/await)
    ├── Storage/      # DataStore (UserDefaults wrapper)
    ├── Extensions/   # Date, UserDefaults helpers
    └── Utilities/    # Constants, FormatterHelper
```

Business logic belongs in managers/services. Prefer `async/await` over completion handlers.

## Code conventions

- Organize with `// MARK: -` sections (Properties → Initialization → Public Methods → Private Methods)
- Structs for data models (`Codable`, `Equatable`); enums for constants
- Use Swift type inference where unambiguous
- Document public APIs with doc comments (`///`)
- Extract complex SwiftUI sub-views into named structs

## Git

Follow `CONTRIBUTING.md` for all development conventions. The following **override global defaults**:

**Issue and PR templates:** Use the templates in `.github/` for work on this fork. If contributing to upstream, follow the lighter format described in `CONTRIBUTING.md` (macOS version, steps to reproduce, expected vs actual, screenshots, Console logs) — do not use our templates there.

**Commits:** `<type>(<scope>): <description>` — scopes are required here (overrides global no-scope rule)

Common scopes: `api`, `menubar`, `statusline`, `settings`, `services`, `models`, `ui`

**Branches:** `feat/`, `fix/`, `docs/`, `refactor/`, `chore/` prefixes (overrides global `issue-<id>-<slug>` convention)

**Remote:** `origin` → `https://github.com/kynoptic/Claude-Usage-Tracker.git` (your fork)

> [!CAUTION]
> **This is a fork. The upstream (`hamed-elfayome/Claude-Usage-Tracker`) is idle.**
> **NEVER push, open PRs, file issues, or interact with upstream in any way.**
> All work — commits, issues, PRs, releases — happens exclusively on this fork (`kynoptic/Claude-Usage-Tracker`).
> There are no exceptions.

Avoid large refactors for now. If upstream becomes active again, we want to be able to contribute back cleanly without a tangled diff.

## Deploy to /Applications

Always pull latest before building, then remove the old bundle before copying — `cp -R` silently skips overwriting an existing `.app` directory, leaving the stale binary in place.

```bash
git pull origin main

xcodebuild clean build -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

DERIVED=$(xcodebuild -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Release \
  -showBuildSettings CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  | awk '/BUILT_PRODUCTS_DIR/{print $3}')

rm -rf "/Applications/Claude Usage.app"
cp -R "$DERIVED/Claude Usage.app" "/Applications/"
```

Use `clean build` (not just `build`) when verifying a fix — incremental Release builds can reuse stale object files and ship the old behaviour.

## Release

1. Bump `MARKETING_VERSION` in `project.pbxproj`
2. Update `CHANGELOG.md`
3. Commit: `chore(release): bump version to X.Y.Z`
4. Tag: `git tag vX.Y.Z && git push origin main --tags`
5. CI creates a draft release — review and publish manually
