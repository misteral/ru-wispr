#!/bin/bash
set -euo pipefail

BINARY="${1:-.build/release/ru-wisper}"
APP_DIR="${2:-RuWisper.app}"
VERSION="${3:-0.3.0}"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/ru-wisper"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [ -d "$REPO_DIR/Resources/Audio" ]; then
    cp -R "$REPO_DIR/Resources/Audio" "$APP_DIR/Contents/Resources/Audio"
fi

cat > "$APP_DIR/Contents/Info.plist" << PLIST
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
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>RuWisper needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier co.itbeaver.ru-wisper "$APP_DIR"

echo "Built $APP_DIR"
