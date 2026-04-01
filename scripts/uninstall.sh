#!/bin/bash
set -euo pipefail

echo "Uninstalling Dikto..."

echo "  Stopping service..."
brew services stop dikto 2>/dev/null || true

echo "  Removing formula..."
brew uninstall dikto 2>/dev/null || true

echo "  Removing tap..."
brew untap misteral/dikto 2>/dev/null || true

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
rm -f /opt/homebrew/var/log/dikto.log

echo "  Resetting permissions..."
tccutil reset Accessibility co.itbeaver.dikto 2>/dev/null || true

echo ""
echo "Dikto has been completely uninstalled."
