#!/bin/bash
set -euo pipefail

echo "==> Stopping any running instances..."
pkill -f "ru-wisper start" 2>/dev/null || true
brew services stop ru-wisper 2>/dev/null || true
sleep 1

echo "==> Building from source..."
swift build -c release 2>&1 | tail -1

echo "==> Bundling app..."
bash scripts/bundle-app.sh .build/release/ru-wisper RuWisper.app dev
rm -rf ~/Applications/RuWisper.app
cp -R RuWisper.app ~/Applications/RuWisper.app
rm -rf RuWisper.app

echo "==> Registering app bundle..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f ~/Applications/RuWisper.app

echo "==> Resetting permissions (simulates install.sh upgrade)..."
tccutil reset Accessibility com.human37.ru-wisper 2>/dev/null || true
tccutil reset Microphone com.human37.ru-wisper 2>/dev/null || true

echo ""
echo "==> Launching RuWisper..."
echo "   You should be prompted for microphone and accessibility permissions."
echo "   The menu bar should show a lock icon while waiting."
echo ""
open ~/Applications/RuWisper.app --args start
