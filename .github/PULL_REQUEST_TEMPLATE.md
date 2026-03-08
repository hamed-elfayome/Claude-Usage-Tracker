## Description

<!-- Briefly describe what this PR does and why -->

## Changes

-

## Screenshots / Screen Recordings

<!-- REQUIRED for any visual/UI changes. Please attach screenshots or screen recordings of the running app showing your changes. PRs with visual changes that don't include screenshots will not be reviewed. -->

<!-- If your change is not visual (e.g., logic-only, refactoring), write "N/A - no visual changes" -->

## Important Guidelines

- **Do NOT use App Groups Keychain with app group identifiers.** This app is distributed outside the App Store via a Developer ID certificate. App Group entitlements require Keychain access prompts on every launch, which breaks the user experience. Use standard `UserDefaults` and standard Keychain access (without group identifiers) instead.
- Follow existing code patterns and architecture (MVVM, protocol-oriented)
- Add localization keys for any new user-facing strings (9 languages supported)
- Test on macOS 14.0+ (Sonoma)

## Checklist

- [ ] I have tested these changes on a running build
- [ ] I have attached screenshots/recordings for any visual changes
- [ ] I have not introduced App Group or grouped Keychain usage
- [ ] I have added localization keys for any new user-facing strings
