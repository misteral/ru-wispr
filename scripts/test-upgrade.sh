#!/bin/bash
set -euo pipefail

echo "==> Stopping any running instances..."
pkill -f "dikto start" 2>/dev/null || true
brew services stop dikto 2>/dev/null || true
sleep 1

echo "==> Building from source..."
swift build -c release 2>&1 | tail -1

echo "==> Bundling app..."
bash scripts/bundle-app.sh .build/release/dikto Dikto.app dev
rm -rf ~/Applications/Dikto.app
cp -R Dikto.app ~/Applications/Dikto.app
rm -rf Dikto.app

echo "==> Registering app bundle..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f ~/Applications/Dikto.app

echo "==> Resetting permissions (simulates install.sh upgrade)..."
tccutil reset Accessibility co.itbeaver.dikto 2>/dev/null || true
tccutil reset Microphone co.itbeaver.dikto 2>/dev/null || true

echo ""
echo "==> Launching Dikto..."
echo "   You should be prompted for microphone and accessibility permissions."
echo "   The menu bar should show a lock icon while waiting."
echo ""
open ~/Applications/Dikto.app --args start
