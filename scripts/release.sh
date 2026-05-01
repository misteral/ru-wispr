#!/bin/bash
# Build, sign, notarize, and package Dikto for distribution
set -euo pipefail

VERSION="1.0.0"
APP_NAME="Dikto"
BUNDLE_ID="co.itbeaver.dikto"
SIGNING_IDENTITY="Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)"
TEAM_ID="8HR3ZJZ5MZ"

# --- Configuration ---
# Set these or pass as env vars:
#   APPLE_ID       — your Apple ID email
#   APP_PASSWORD   — app-specific password (generate at appleid.apple.com)
APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

BUILD_DIR="$(pwd)/dist"
DERIVED_DATA="$(pwd)/.build/xcode-release"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
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

check_xcode_build_prereqs() {
    local dev_dir metal_component_status

    if ! xcodebuild -version >/dev/null 2>&1; then
        fail "xcodebuild is not available. Install Xcode and select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi

    dev_dir="$(xcode-select -p 2>/dev/null || true)"
    if [ "$dev_dir" = "/Library/Developer/CommandLineTools" ]; then
        fail "xcodebuild is pointing at Command Line Tools, not full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi

    metal_component_status="$(xcodebuild -showComponent MetalToolchain 2>/dev/null || true)"
    if echo "$metal_component_status" | grep -q "Status: uninstalled"; then
        fail "Xcode Metal Toolchain is not installed. Run: xcodebuild -downloadComponent MetalToolchain"
    fi
}

# --- Verify signing identity ---
step "Checking signing identity..."
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    fail "Signing identity not found: $SIGNING_IDENTITY"
fi
echo "Found: $SIGNING_IDENTITY"

# --- Build ---
check_xcode_build_prereqs
mkdir -p "$BUILD_DIR"
rm -rf "$DERIVED_DATA"

step "Building with xcodebuild (Release + Metal shaders)..."
if ! xcodebuild -scheme dikto -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build >"$BUILD_LOG" 2>&1; then
    tail -40 "$BUILD_LOG"
    echo ""
    if grep -q "missing Metal Toolchain" "$BUILD_LOG"; then
        fail "Xcode Metal Toolchain is not installed. Run: xcodebuild -downloadComponent MetalToolchain"
    elif grep -q "requires Xcode, but active developer directory '/Library/Developer/CommandLineTools'" "$BUILD_LOG"; then
        fail "xcodebuild is pointing at Command Line Tools, not full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    else
        fail "xcodebuild failed. Full log: $BUILD_LOG"
    fi
fi

tail -3 "$BUILD_LOG"

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
BINARY="$PRODUCTS/dikto"
METALLIB_BUNDLE="$PRODUCTS/mlx-swift_Cmlx.bundle"
METALLIB="$METALLIB_BUNDLE/Contents/Resources/default.metallib"

if [ ! -f "$BINARY" ] || [ ! -f "$METALLIB" ]; then
    fail "Build artifacts not found in $PRODUCTS"
fi
echo "Binary: $BINARY"
echo "Metal:  $METALLIB_BUNDLE"

# --- Assemble .app bundle ---
step "Assembling $APP_NAME.app..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/dikto"

# Metal library — MLX searches in multiple locations:
#   1. <binary_dir>/mlx.metallib (colocated with binary)
#   2. Bundle.main.resourceURL (Contents/Resources/)
#   3. SwiftPM bundle via allBundles
# Place in both MacOS/ (colocated) and Resources/ (bundle search) for reliability
cp "$METALLIB" "$APP_DIR/Contents/MacOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/MacOS/"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/Resources/"

# Resources
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [ -d "Resources/Audio" ]; then
    cp -R "Resources/Audio" "$APP_DIR/Contents/Resources/Audio"
fi
if [ -f "Resources/dictionary.json" ]; then
    cp "Resources/dictionary.json" "$APP_DIR/Contents/Resources/dictionary.json"
fi

# GigaAM RNNT model — bundle for distribution.
# Search order matches build.sh: project Resources/ first (so the repo is the
# source of truth for what ships), then user data dir, then legacy ru-wisper
# path. Distribution builds MUST include the model — fail loudly if missing
# so a broken DMG never reaches users.
PROJECT_GIGAAM_MODEL="$(pwd)/Resources/gigaam-v3-rnnt-mlx"
APP_SUPPORT_GIGAAM_MODEL="$HOME/Library/Application Support/Dikto/models/gigaam-v3-rnnt-mlx"
LEGACY_GIGAAM_MODEL="$HOME/.config/ru-wisper/models/gigaam-v3-rnnt-mlx"

if [ -n "${GIGAAM_MODEL:-}" ]; then
    GIGAAM_MODEL_DIR="$GIGAAM_MODEL"
elif [ -f "$PROJECT_GIGAAM_MODEL/config.json" ] && [ -f "$PROJECT_GIGAAM_MODEL/model.safetensors" ]; then
    GIGAAM_MODEL_DIR="$PROJECT_GIGAAM_MODEL"
elif [ -f "$APP_SUPPORT_GIGAAM_MODEL/config.json" ] && [ -f "$APP_SUPPORT_GIGAAM_MODEL/model.safetensors" ]; then
    GIGAAM_MODEL_DIR="$APP_SUPPORT_GIGAAM_MODEL"
elif [ -f "$LEGACY_GIGAAM_MODEL/config.json" ] && [ -f "$LEGACY_GIGAAM_MODEL/model.safetensors" ]; then
    GIGAAM_MODEL_DIR="$LEGACY_GIGAAM_MODEL"
else
    GIGAAM_MODEL_DIR=""
fi

if [ -z "$GIGAAM_MODEL_DIR" ] || [ ! -f "$GIGAAM_MODEL_DIR/config.json" ] || [ ! -f "$GIGAAM_MODEL_DIR/model.safetensors" ]; then
    echo ""
    echo "Checked:"
    echo "  $PROJECT_GIGAAM_MODEL"
    echo "  $APP_SUPPORT_GIGAAM_MODEL"
    echo "  $LEGACY_GIGAAM_MODEL"
    echo "Or set GIGAAM_MODEL=/path/to/gigaam-v3-rnnt-mlx"
    fail "GigaAM RNNT model not found — refusing to build a release without it"
fi

step "Bundling GigaAM RNNT model from $GIGAAM_MODEL_DIR..."
cp -R "$GIGAAM_MODEL_DIR" "$APP_DIR/Contents/Resources/gigaam-v3-rnnt-mlx"
du -sh "$APP_DIR/Contents/Resources/gigaam-v3-rnnt-mlx"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>dikto</string>
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
    <string>Dikto needs microphone access to record speech for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dikto needs accessibility access to insert transcribed text.</string>
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
ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/Dikto.entitlements"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR/Contents/MacOS/dikto"

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
