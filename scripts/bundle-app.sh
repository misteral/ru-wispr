#!/bin/bash
set -euo pipefail

BINARY="${1:-.build/release/dikto}"
APP_DIR="${2:-Dikto.app}"
VERSION="${3:-0.3.0}"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/dikto"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [ -d "$REPO_DIR/Resources/Audio" ]; then
    cp -R "$REPO_DIR/Resources/Audio" "$APP_DIR/Contents/Resources/Audio"
fi

if [ -f "$REPO_DIR/Resources/dictionary.json" ]; then
    cp "$REPO_DIR/Resources/dictionary.json" "$APP_DIR/Contents/Resources/dictionary.json"
fi

if [ -f "$REPO_DIR/Resources/gigaam-v3-rnnt-mlx/config.json" ] && [ -f "$REPO_DIR/Resources/gigaam-v3-rnnt-mlx/model.safetensors" ]; then
    cp -R "$REPO_DIR/Resources/gigaam-v3-rnnt-mlx" "$APP_DIR/Contents/Resources/gigaam-v3-rnnt-mlx"
fi

cat > "$APP_DIR/Contents/Info.plist" << PLIST
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
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dikto needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier co.itbeaver.dikto "$APP_DIR"

echo "Built $APP_DIR"
