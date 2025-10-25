#!/bin/bash

# Build script for Claude Usage Tracker Installer
# Creates a professional .pkg installer for macOS

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "================================================"
echo "  Claude Usage Tracker - Installer Builder"
echo "================================================"
echo ""

# Configuration
PROJECT_NAME="Claude Usage"
SCHEME="Claude Usage"
APP_NAME="Claude Usage.app"
BUILD_DIR="build-pkg-$(date +%s)"
PKG_DIR="pkg"
PKG_ROOT="$PKG_DIR/root"
PKG_SCRIPTS="$PKG_DIR/scripts"
IDENTIFIER="com.claudeusage.tracker"
VERSION="1.0.3"
PKG_NAME="ClaudeUsageTracker-v${VERSION}.pkg"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Step 1: Check Xcode
echo -e "${BLUE}Step 1/8:${NC} Checking Xcode..."
if ! xcodebuild -version &> /dev/null; then
    echo -e "${RED}❌ Xcode license not accepted${NC}"
    echo ""
    echo "Please run: sudo xcodebuild -license accept"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode ready"
echo ""

# Step 2: Clean previous builds
echo -e "${BLUE}Step 2/8:${NC} Cleaning previous builds..."
rm -rf "$PKG_DIR" 2>/dev/null || true
rm -f *.pkg 2>/dev/null || true
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_SCRIPTS"
echo -e "${GREEN}✓${NC} Clean complete"
echo ""

# Step 3: Build the app
echo -e "${BLUE}Step 3/8:${NC} Building app (Release configuration)..."
echo "This may take a few minutes..."
echo ""

xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -arch arm64 \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | grep -E "^\*\*|^===|error:|warning:" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓${NC} Build successful"
echo ""

# Find the built app
BUILT_APP=$(find "$BUILD_DIR" -name "$APP_NAME" -type d | head -n 1)
if [ -z "$BUILT_APP" ]; then
    echo -e "${RED}❌ Could not find built app${NC}"
    exit 1
fi

# Step 4: Ad-hoc code signing
echo -e "${BLUE}Step 4/8:${NC} Signing app (ad-hoc signature)..."
echo ""

# Sign all frameworks and executables
find "$BUILT_APP" -type f \( -name "*.dylib" -o -name "*.framework" -o -perm +111 \) -exec codesign -s - --force --deep {} \; 2>/dev/null || true

# Sign the app bundle
codesign -s - --force --deep "$BUILT_APP"

if codesign -v "$BUILT_APP" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} App signed successfully"
else
    echo -e "${YELLOW}⚠${NC} Signature verification failed (OK for ad-hoc signing)"
fi
echo ""

# Step 5: Copy app to package root
echo -e "${BLUE}Step 5/8:${NC} Preparing package structure..."
ditto "$BUILT_APP" "$PKG_ROOT/Applications/$APP_NAME"
echo -e "${GREEN}✓${NC} App copied to package root"
echo ""

# Step 6: Copy installation scripts
echo -e "${BLUE}Step 6/8:${NC} Preparing installation scripts..."
cp "scripts/postinstall" "$PKG_SCRIPTS/"
chmod +x "$PKG_SCRIPTS/postinstall"
echo -e "${GREEN}✓${NC} Scripts prepared"
echo ""

# Step 7: Build the package WITHOUT bundle relocation
echo -e "${BLUE}Step 7/8:${NC} Building installer package..."
echo ""

# Create component plist to disable relocation
cat > /tmp/component.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleHasStrictIdentifier</key>
        <true/>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>BundleIsVersionChecked</key>
        <true/>
        <key>BundleOverwriteAction</key>
        <string>upgrade</string>
        <key>RootRelativeBundlePath</key>
        <string>Applications/Claude Usage.app</string>
    </dict>
</array>
</plist>
EOF

pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$PKG_SCRIPTS" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    --component-plist /tmp/component.plist \
    "$PKG_NAME"

rm /tmp/component.plist

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Package created: $PKG_NAME"
else
    echo -e "${RED}❌ Package creation failed${NC}"
    exit 1
fi
echo ""

# Step 8: Generate SHA256 hash
echo -e "${BLUE}Step 8/8:${NC} Generating SHA256 hash..."
HASH=$(shasum -a 256 "$PKG_NAME" | cut -d ' ' -f 1)
echo "$HASH" > "$PKG_NAME.sha256"
echo -e "${GREEN}✓${NC} Hash generated"
echo ""

# Clean up build directory
rm -rf "$BUILD_DIR" 2>/dev/null || true

# Get file size
PKG_SIZE=$(du -h "$PKG_NAME" | cut -f1)

# Final summary
echo "================================================"
echo -e "${GREEN}  Build Complete!${NC}"
echo "================================================"
echo ""
echo "Output files:"
echo "  📦 $PKG_NAME ($PKG_SIZE)"
echo "  🔐 $PKG_NAME.sha256"
echo ""
echo "SHA256: $HASH"
echo ""
echo "What this installer does:"
echo "  ✓ Installs app to /Applications/Claude Usage.app"
echo "  ✓ Removes quarantine attribute (no security warning!)"
echo "  ✓ Sets proper permissions"
echo "  ✓ NO RELOCATION - always installs to /Applications"
echo ""
echo "User experience:"
echo "  1. Double-click the .pkg file"
echo "  2. Click 'Continue' → 'Install'"
echo "  3. Enter password"
echo "  4. Done! App is in /Applications"
echo ""
echo "Distribution checklist:"
echo "  ☐ Test the installer"
echo "  ☐ Upload $PKG_NAME to GitHub releases"
echo "  ☐ Include SHA256 hash in release notes"
echo ""
