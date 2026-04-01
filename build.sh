#!/bin/bash
# Build dikto with MLX Metal support and install to /Applications
set -euo pipefail

VERSION="1.0.0"
BUILD_DIR="$(pwd)/.build/xcode"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"

check_xcode_build_prereqs() {
    local dev_dir metal_component_status

    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "Error: xcodebuild is not available. Install Xcode and select it with:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    dev_dir="$(xcode-select -p 2>/dev/null || true)"
    if [ "$dev_dir" = "/Library/Developer/CommandLineTools" ]; then
        echo "Error: xcodebuild is pointing at Command Line Tools, not full Xcode. Run:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    metal_component_status="$(xcodebuild -showComponent MetalToolchain 2>/dev/null || true)"
    if echo "$metal_component_status" | grep -q "Status: uninstalled"; then
        echo "Error: Xcode Metal Toolchain is not installed. Run:"
        echo "  xcodebuild -downloadComponent MetalToolchain"
        exit 1
    fi
}

mkdir -p "$BUILD_DIR"
check_xcode_build_prereqs

echo "==> Building with xcodebuild (compiles Metal shaders)..."
# Use project-local derivedDataPath for deterministic output
if ! xcodebuild -scheme dikto -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    build >"$BUILD_LOG" 2>&1; then
    tail -40 "$BUILD_LOG"
    echo ""
    if grep -q "missing Metal Toolchain" "$BUILD_LOG"; then
        echo "Error: Xcode Metal Toolchain is not installed. Run:"
        echo "  xcodebuild -downloadComponent MetalToolchain"
    elif grep -q "requires Xcode, but active developer directory '/Library/Developer/CommandLineTools'" "$BUILD_LOG"; then
        echo "Error: xcodebuild is pointing at Command Line Tools, not full Xcode. Run:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    else
        echo "Error: xcodebuild failed. Full log: $BUILD_LOG"
    fi
    exit 1
fi

tail -3 "$BUILD_LOG"

PRODUCTS="$BUILD_DIR/Build/Products/Release"
DERIVED="$PRODUCTS/dikto"
METALLIB_BUNDLE="$PRODUCTS/mlx-swift_Cmlx.bundle"
METALLIB="$METALLIB_BUNDLE/Contents/Resources/default.metallib"

if [ ! -f "$DERIVED" ] || [ ! -f "$METALLIB" ]; then
    echo "Error: Build artifacts not found in $PRODUCTS"
    exit 1
fi

# Verify binary was actually rebuilt (modified within last 60 seconds)
BINARY_AGE=$(( $(date +%s) - $(stat -f %m "$DERIVED") ))
if [ "$BINARY_AGE" -gt 60 ]; then
    echo "⚠️  Binary is ${BINARY_AGE}s old — xcodebuild may have used stale cache"
    echo "    Run: rm -rf $BUILD_DIR && bash build.sh"
    echo "    Continuing anyway..."
fi

echo "==> Installing to /Applications/Dikto.app..."

APP_DIR="/Applications/Dikto.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Force remove the app from TCC (Privacy & Security) database to reset permissions
# (This doesn't always work perfectly without sudo, but helps sometimes)
tccutil reset All co.itbeaver.dikto 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Binary + Metal library (place in both MacOS/ and Resources/ for MLX discovery)
cp "$DERIVED" "$MACOS/dikto"
cp "$METALLIB" "$MACOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$MACOS/"
cp -R "$METALLIB_BUNDLE" "$RESOURCES/"

# Resources
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
if [ -d "Resources/Audio" ]; then
    cp -R "Resources/Audio" "$RESOURCES/Audio"
fi

# GigaAM RNNT model — bundle if available
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

if [ -n "$GIGAAM_MODEL_DIR" ] && [ -f "$GIGAAM_MODEL_DIR/config.json" ] && [ -f "$GIGAAM_MODEL_DIR/model.safetensors" ]; then
    echo "==> Bundling GigaAM RNNT model from $GIGAAM_MODEL_DIR..."
    cp -R "$GIGAAM_MODEL_DIR" "$RESOURCES/gigaam-v3-rnnt-mlx"
else
    echo "==> GigaAM RNNT model not found (skipping bundle)"
    echo "    Checked: $PROJECT_GIGAAM_MODEL"
    echo "             $APP_SUPPORT_GIGAAM_MODEL"
    echo "             $LEGACY_GIGAAM_MODEL"
    echo "    Or set GIGAAM_MODEL=/path/to/gigaam-v3-rnnt-mlx"
fi

# Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>dikto</string>
    <key>CFBundleIdentifier</key>
    <string>co.itbeaver.dikto</string>
    <key>CFBundleName</key>
    <string>Dikto</string>
    <key>CFBundleDisplayName</key>
    <string>Dikto</string>
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

echo "==> Code signing..."
codesign --force --deep --sign - --identifier co.itbeaver.dikto "$APP_DIR"

echo ""
echo "✅ Installed: /Applications/Dikto.app"
du -sh "$APP_DIR"
echo ""
echo "Launch: open /Applications/Dikto.app"
echo "CLI:    /Applications/Dikto.app/Contents/MacOS/dikto status"
