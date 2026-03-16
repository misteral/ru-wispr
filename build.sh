#!/bin/bash
# Build ru-wisper with MLX Metal support and install to /Applications
set -e

VERSION="1.0.0"
BUILD_DIR="$(pwd)/.build/xcode"

echo "==> Building with xcodebuild (compiles Metal shaders)..."
# Use project-local derivedDataPath for deterministic output
xcodebuild -scheme ru-wisper -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | tail -3

PRODUCTS="$BUILD_DIR/Build/Products/Release"
DERIVED="$PRODUCTS/ru-wisper"
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

echo "==> Installing to /Applications/RuWisper.app..."

APP_DIR="/Applications/RuWisper.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Force remove the app from TCC (Privacy & Security) database to reset permissions
# (This doesn't always work perfectly without sudo, but helps sometimes)
tccutil reset All co.itbeaver.ru-wisper 2>/dev/null || true

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Binary + Metal library (place in both MacOS/ and Resources/ for MLX discovery)
cp "$DERIVED" "$MACOS/ru-wisper"
cp "$METALLIB" "$MACOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$MACOS/"
cp -R "$METALLIB_BUNDLE" "$RESOURCES/"

# Resources
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
if [ -d "Resources/Audio" ]; then
    cp -R "Resources/Audio" "$RESOURCES/Audio"
fi

# GigaAM RNNT model — bundle if available
GIGAAM_MODEL="${GIGAAM_MODEL:-$HOME/.config/ru-wisper/models/gigaam-v3-rnnt-mlx}"
if [ -f "$GIGAAM_MODEL/config.json" ] && [ -f "$GIGAAM_MODEL/model.safetensors" ]; then
    echo "==> Bundling GigaAM RNNT model..."
    cp -R "$GIGAAM_MODEL" "$RESOURCES/gigaam-v3-rnnt-mlx"
else
    echo "==> GigaAM RNNT model not found at $GIGAAM_MODEL (skipping bundle)"
    echo "    Set GIGAAM_MODEL=/path/to/gigaam-v3-rnnt-mlx to bundle it"
fi

# Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ru-wisper</string>
    <key>CFBundleIdentifier</key>
    <string>co.itbeaver.ru-wisper</string>
    <key>CFBundleName</key>
    <string>RuWisper</string>
    <key>CFBundleDisplayName</key>
    <string>RuWisper</string>
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

echo "==> Code signing..."
codesign --force --deep --sign - --identifier co.itbeaver.ru-wisper "$APP_DIR"

echo ""
echo "✅ Installed: /Applications/RuWisper.app"
du -sh "$APP_DIR"
echo ""
echo "Launch: open /Applications/RuWisper.app"
echo "CLI:    /Applications/RuWisper.app/Contents/MacOS/ru-wisper status"
