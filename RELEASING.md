# Release Process

This document describes how to create a new release of Claude Usage Tracker.

## Prerequisites

- Xcode with command line tools
- Git configured with push access to the repository
- All changes committed and pushed to `main` branch

## Release Checklist

### 1. Update Version Numbers

Edit `Claude Usage.xcodeproj/project.pbxproj`:

```bash
# Update MARKETING_VERSION (e.g., 2.1.0 → 2.2.0)
# Update CURRENT_PROJECT_VERSION (increment build number, e.g., 2 → 3)
```

**Important:**
- `MARKETING_VERSION` is the user-facing version (e.g., 2.2.0)
- `CURRENT_PROJECT_VERSION` is the build number used by Sparkle for update detection
- **ALWAYS increment CURRENT_PROJECT_VERSION** for each release, even for patches!

### 2. Update CHANGELOG.md

Add a new section at the top with:
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features...

### Changed
- Changes to existing features...

### Fixed
- Bug fixes...
```

### 3. Commit Version Changes

```bash
git add Claude\ Usage.xcodeproj/project.pbxproj CHANGELOG.md
git commit -m "chore: Bump version to X.Y.Z"
git push
```

### 4. Create and Push Tag

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z: Brief description

- Key feature 1
- Key feature 2
- Bug fixes"

git push origin vX.Y.Z
```

### 5. Wait for Workflows

The tag push triggers three automated workflows:

1. **Release workflow** (~5-10 minutes)
   - Builds the app
   - Signs with Apple Developer certificate
   - Notarizes with Apple
   - Creates GitHub release with ZIP file

2. **Generate Appcast workflow** (triggers after release)
   - Downloads the release
   - Generates appcast.xml with EdDSA signature
   - Updates gh-pages with new version

3. **Update Homebrew Cask workflow** (triggers after release)
   - Automatically updates Homebrew formula

Monitor at: `https://github.com/hamed-elfayome/Claude-Usage-Tracker/actions`

### 6. Verify Release

1. Check GitHub releases page for the new release
2. Verify appcast: `https://hamed-elfayome.github.io/Claude-Usage-Tracker/appcast.xml`
3. Test in-app update:
   - Run an older version of the app
   - Check for updates
   - Verify new version appears and installs correctly

## Troubleshooting

### Update not showing in app

- Check `CURRENT_PROJECT_VERSION` was incremented (not just `MARKETING_VERSION`)
- Verify appcast.xml has higher `<sparkle:version>` number
- Clear app caches: `~/Library/Caches/HamedElfayome.Claude-Usage/`

### Signature validation error

- Workflow regenerates signatures automatically
- If you manually edited appcast.xml, it will fail
- Re-run "Generate Appcast" workflow to regenerate with correct signatures

### Workflow failures

- **Release workflow**: Check code signing certificates and notarization credentials
- **Appcast workflow**: Verify release ZIP was created and SPARKLE_PRIVATE_KEY secret exists
- **Homebrew workflow**: Check RELEASE_TOKEN has proper permissions

## Quick Reference

```bash
# Full release in 4 commands:
sed -i '' 's/MARKETING_VERSION = X.Y.Z/MARKETING_VERSION = X.Y.Z+1/g' Claude\ Usage.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = N/CURRENT_PROJECT_VERSION = N+1/g' Claude\ Usage.xcodeproj/project.pbxproj
git add -A && git commit -m "chore: Bump version to X.Y.Z+1" && git push
git tag -a vX.Y.Z+1 -m "Release vX.Y.Z+1" && git push origin vX.Y.Z+1
```

## Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **Major** (X.0.0): Breaking changes, major new features
- **Minor** (x.Y.0): New features, backwards compatible
- **Patch** (x.y.Z): Bug fixes, minor improvements

Build number (`CURRENT_PROJECT_VERSION`) always increments sequentially: 1, 2, 3, 4...
