#!/bin/bash
# Build, sign, notarize, and package Dikto Pro RU (Russian commercial edition)
# as a separate, side-by-side installable DMG.
#
# Differences from scripts/release.sh:
#   * DIKTO_FLAVOR=pro_ru   → ProductFlavor.current == .proRU
#   * APP_NAME="Dikto Pro"  → user-visible name + DMG filename
#   * BUNDLE_ID=ru.diktopro → separate TCC permissions, can coexist with free Dikto
#   * Russian CFBundleDisplayName
#   * Info.plist embeds DIKTOLicenseServer (default: https://api.dikto.itbeaver.co)
#     and DIKTOBuyURL (default: https://dikto.itbeaver.co/buy); override via env vars
#     to point at staging.
set -euo pipefail

VERSION="${DIKTO_PRO_VERSION:-1.0.0}"
APP_NAME="Dikto Pro"
APP_NAME_FS="Dikto-Pro"   # filesystem-safe variant for paths/DMGs
BUNDLE_ID="ru.diktopro"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)}"
TEAM_ID="${TEAM_ID:-8HR3ZJZ5MZ}"

LICENSE_SERVER="${DIKTO_LICENSE_SERVER:-https://api.dikto.itbeaver.co}"
BUY_URL="${DIKTO_BUY_URL:-https://dikto.itbeaver.co/buy}"

APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

BUILD_DIR="$(pwd)/dist-pro-ru"
DERIVED_DATA="$(pwd)/.build/xcode-release-pro-ru"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME_FS-$VERSION.dmg"

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

step "Checking signing identity..."
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    fail "Signing identity not found: $SIGNING_IDENTITY"
fi
echo "Found: $SIGNING_IDENTITY"

check_xcode_build_prereqs
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
rm -rf "$DERIVED_DATA"

step "Building with xcodebuild (Pro RU flavor, Release + Metal shaders)..."
# Inject the flavor flag through both DIKTO_FLAVOR (read by Package.swift) and
# OTHER_SWIFT_FLAGS so the same swift-build pipeline picks it up regardless of
# whether SwiftPM is invoked directly or through xcodebuild.
DIKTO_FLAVOR=pro_ru \
xcodebuild -scheme dikto -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    OTHER_SWIFT_FLAGS='$(inherited) -D DIKTO_PRO_RU' \
    build >"$BUILD_LOG" 2>&1 || {
    tail -40 "$BUILD_LOG"
    echo ""
    if grep -q "missing Metal Toolchain" "$BUILD_LOG"; then
        fail "Xcode Metal Toolchain is not installed. Run: xcodebuild -downloadComponent MetalToolchain"
    elif grep -q "requires Xcode, but active developer directory '/Library/Developer/CommandLineTools'" "$BUILD_LOG"; then
        fail "xcodebuild is pointing at Command Line Tools, not full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    else
        fail "xcodebuild failed. Full log: $BUILD_LOG"
    fi
}

tail -3 "$BUILD_LOG"

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
BINARY="$PRODUCTS/dikto"
METALLIB_BUNDLE="$PRODUCTS/mlx-swift_Cmlx.bundle"
METALLIB="$METALLIB_BUNDLE/Contents/Resources/default.metallib"

if [ ! -f "$BINARY" ] || [ ! -f "$METALLIB" ]; then
    fail "Build artifacts not found in $PRODUCTS"
fi

step "Assembling $APP_NAME.app..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/dikto"

cp "$METALLIB" "$APP_DIR/Contents/MacOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/MacOS/"
cp -R "$METALLIB_BUNDLE" "$APP_DIR/Contents/Resources/"

cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [ -d "Resources/Audio" ]; then
    cp -R "Resources/Audio" "$APP_DIR/Contents/Resources/Audio"
fi
if [ -f "Resources/dictionary.json" ]; then
    cp "Resources/dictionary.json" "$APP_DIR/Contents/Resources/dictionary.json"
fi

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
    fail "GigaAM RNNT model not found — refusing to build Pro RU release without it"
fi

step "Bundling GigaAM RNNT model from $GIGAAM_MODEL_DIR..."
cp -R "$GIGAAM_MODEL_DIR" "$APP_DIR/Contents/Resources/gigaam-v3-rnnt-mlx"
du -sh "$APP_DIR/Contents/Resources/gigaam-v3-rnnt-mlx"

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
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dikto Pro использует микрофон для распознавания речи.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dikto Pro вставляет распознанный текст там, где стоит курсор.</string>
    <key>DIKTOLicenseServer</key>
    <string>${LICENSE_SERVER}</string>
    <key>DIKTOBuyURL</key>
    <string>${BUY_URL}</string>
</dict>
</plist>
PLIST

echo "App bundle: $APP_DIR"
du -sh "$APP_DIR"

step "Signing with Developer ID..."

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/MacOS/mlx.metallib"

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/Resources/mlx-swift_Cmlx.bundle"

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR/Contents/MacOS/mlx-swift_Cmlx.bundle"

ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/Dikto.entitlements"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR/Contents/MacOS/dikto"

codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"

echo "Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"
echo "Signature OK ✓"

spctl --assess --type execute --verbose "$APP_DIR" 2>&1 || warn "spctl check failed (expected before notarization)"

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

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "DMG: $DMG_PATH"
du -sh "$DMG_PATH"

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
    echo -e "${GREEN}✅ Готово! Dikto Pro RU собран и нотаризован:${NC}"
    echo "   $DMG_PATH"
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
    echo -e "${GREEN}✅ Подписанный Pro RU DMG готов:${NC}"
    echo "   $DMG_PATH"
fi
