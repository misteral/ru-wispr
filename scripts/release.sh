#!/bin/bash
# Build, sign, notarize, and package RuWisper for distribution
set -euo pipefail

VERSION="1.0.0"
APP_NAME="RuWisper"
BUNDLE_ID="com.human37.ru-wisper"
SIGNING_IDENTITY="Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)"
TEAM_ID="8HR3ZJZ5MZ"

# --- Configuration ---
# Set these or pass as env vars:
#   APPLE_ID       — your Apple ID email
#   APP_PASSWORD   — app-specific password (generate at appleid.apple.com)
APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

BUILD_DIR="$(pwd)/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${GREEN}==> $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }

# --- Verify signing identity ---
step "Checking signing identity..."
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    fail "Signing identity not found: $SIGNING_IDENTITY"
fi
echo "Found: $SIGNING_IDENTITY"

# --- Build ---
step "Building with xcodebuild (Release + Metal shaders)..."
xcodebuild -scheme ru-wisper -configuration Release -destination "platform=macOS" build -quiet 2>/dev/null

BINARY=$(find ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release -name "ru-wisper" -not -path "*.dSYM*" -maxdepth 1 2>/dev/null | head -1)
METALLIB_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release -name "mlx-swift_Cmlx.bundle" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$BINARY" ] || [ -z "$METALLIB_BUNDLE" ]; then
    fail "Build artifacts not found. Check xcodebuild output."
fi
echo "Binary: $BINARY"
echo "Metal:  $METALLIB_BUNDLE"

# --- Assemble .app bundle ---
step "Assembling $APP_NAME.app..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/ru-wisper"

# Metal library — MLX searches in multiple locations:
#   1. <binary_dir>/mlx.metallib (colocated with binary)
#   2. Bundle.main.resourceURL (Contents/Resources/)
#   3. SwiftPM bundle via allBundles
# Place in both MacOS/ (colocated) and Resources/ (bundle search) for reliability
METALLIB="$METALLIB_BUNDLE/Contents/Resources/default.metallib"
cp "$METALLIB" "$APP_DIR/Contents/MacOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/MacOS/"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/Resources/"

# Resources
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [ -d "Resources/Audio" ]; then
    cp -R "Resources/Audio" "$APP_DIR/Contents/Resources/Audio"
fi

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ru-wisper</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>RuWisper needs microphone access to record speech for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>RuWisper needs accessibility access to insert transcribed text.</string>
</dict>
</plist>
PLIST

echo "App bundle: $APP_DIR"
du -sh "$APP_DIR"

# --- Code sign ---
step "Signing with Developer ID..."

# Sign inside-out: deepest components first

# Sign standalone metallib file
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/MacOS/mlx.metallib"

# Sign Metal bundles (in both locations)
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/Resources/mlx-swift_Cmlx.bundle"

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/MacOS/mlx-swift_Cmlx.bundle"

# Sign the main binary (with entitlements for Hardened Runtime)
ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/RuWisper.entitlements"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR/Contents/MacOS/ru-wisper"

# Sign the entire app
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"

# Verify
echo "Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"
echo "Signature OK ✓"

spctl --assess --type execute --verbose "$APP_DIR" 2>&1 || warn "spctl check failed (expected before notarization)"

# --- Install to /Applications ---
step "Installing to /Applications..."
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
echo "Installed: /Applications/$APP_NAME.app"

# --- Create DMG ---
step "Creating DMG..."

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# Sign the DMG too
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "DMG: $DMG_PATH"
du -sh "$DMG_PATH"

# --- Notarize ---
if [ -n "$APPLE_ID" ] && [ -n "$APP_PASSWORD" ]; then
    step "Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    step "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    echo ""
    echo -e "${GREEN}✅ Done! Ready for distribution:${NC}"
    echo "   $DMG_PATH"
    echo ""
    echo "Verify:  spctl --assess --type open --context context:primary-signature --verbose $DMG_PATH"
else
    echo ""
    warn "Skipping notarization (APPLE_ID and APP_PASSWORD not set)"
    echo ""
    echo "To notarize manually:"
    echo "  xcrun notarytool submit $DMG_PATH \\"
    echo "      --apple-id YOUR_EMAIL \\"
    echo "      --password APP_SPECIFIC_PASSWORD \\"
    echo "      --team-id $TEAM_ID \\"
    echo "      --wait"
    echo "  xcrun stapler staple $DMG_PATH"
    echo ""
    echo -e "${GREEN}✅ Signed DMG ready:${NC}"
    echo "   $DMG_PATH"
fi
