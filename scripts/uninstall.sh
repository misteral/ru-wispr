#!/bin/bash
set -euo pipefail

echo "Uninstalling Dikto..."

echo "  Stopping running app..."
pkill -f "/Dikto.app/Contents/MacOS/dikto" 2>/dev/null || true
pkill -f "dikto start" 2>/dev/null || true
sleep 1

echo "  Removing config (iCloud Drive)..."
rm -rf ~/Library/Mobile\ Documents/com~apple~CloudDocs/Dikto
rm -rf ~/Library/Mobile\ Documents/com~apple~CloudDocs/RuWispr

echo "  Removing data (models, recordings)..."
rm -rf ~/Library/Application\ Support/Dikto
rm -rf ~/Library/Application\ Support/RuWispr

echo "  Removing legacy config..."
rm -rf ~/.config/dikto
rm -rf ~/.config/ru-wisper

echo "  Removing app bundle..."
rm -rf ~/Applications/Dikto.app
rm -rf /Applications/Dikto.app 2>/dev/null || true
rm -rf ~/Applications/RuWisper.app
rm -rf /Applications/RuWisper.app 2>/dev/null || true

echo "  Removing logs..."
rm -f ~/Library/Logs/Dikto.log 2>/dev/null || true
rm -f /tmp/dikto*.log 2>/dev/null || true

echo "  Resetting permissions..."
tccutil reset Accessibility co.itbeaver.dikto 2>/dev/null || true
tccutil reset Microphone co.itbeaver.dikto 2>/dev/null || true

echo ""
echo "Dikto has been completely uninstalled."
