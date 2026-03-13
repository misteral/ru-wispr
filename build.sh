#!/bin/bash
# Build open-wispr with MLX Metal support and install to /Applications
set -e

echo "==> Building with xcodebuild (compiles Metal shaders)..."
xcodebuild -scheme open-wispr -configuration Release -destination "platform=macOS" build -quiet 2>/dev/null

DERIVED=$(find ~/Library/Developer/Xcode/DerivedData/open-wispr-*/Build/Products/Release -name "open-wispr" -not -path "*.dSYM*" -maxdepth 1 2>/dev/null | head -1)
METALLIB_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/open-wispr-*/Build/Products/Release -name "mlx-swift_Cmlx.bundle" -maxdepth 1 2>/dev/null | head -1)
METALLIB="$METALLIB_BUNDLE/Contents/Resources/default.metallib"

if [ -z "$DERIVED" ] || [ -z "$METALLIB" ]; then
    echo "Error: Build artifacts not found"
    exit 1
fi

echo "==> Installing to /Applications/OpenWispr.app..."

APP_DIR="/Applications/OpenWispr.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Binary + Metal library
cp "$DERIVED" "$MACOS/open-wispr"
cp "$METALLIB" "$MACOS/mlx.metallib"
cp -R "$METALLIB_BUNDLE" "$MACOS/"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>open-wispr</string>
    <key>CFBundleIdentifier</key>
    <string>com.openwispr.app</string>
    <key>CFBundleName</key>
    <string>OpenWispr</string>
    <key>CFBundleDisplayName</key>
    <string>OpenWispr</string>
    <key>CFBundleVersion</key>
    <string>0.19.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.19.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenWispr needs microphone access for voice dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>OpenWispr needs accessibility access to insert transcribed text.</string>
</dict>
</plist>
PLIST

echo ""
echo "✅ Installed: /Applications/OpenWispr.app"
du -sh "$APP_DIR"
echo ""
echo "Launch: open /Applications/OpenWispr.app"
echo "CLI:    /Applications/OpenWispr.app/Contents/MacOS/open-wispr status"
