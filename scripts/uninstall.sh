#!/bin/bash
set -euo pipefail

echo "Uninstalling RuWisper..."

echo "  Stopping service..."
brew services stop ru-wisper 2>/dev/null || true

echo "  Removing formula..."
brew uninstall ru-wisper 2>/dev/null || true

echo "  Removing tap..."
brew untap human37/ru-wisper 2>/dev/null || true

echo "  Removing config (iCloud Drive)..."
rm -rf ~/Library/Mobile\ Documents/com~apple~CloudDocs/RuWispr

echo "  Removing data (models, recordings)..."
rm -rf ~/Library/Application\ Support/RuWispr

echo "  Removing legacy config..."
rm -rf ~/.config/ru-wisper

echo "  Removing app bundle..."
rm -rf ~/Applications/RuWisper.app
rm -rf /Applications/RuWisper.app 2>/dev/null || true

echo "  Removing logs..."
rm -f /opt/homebrew/var/log/ru-wisper.log

echo "  Resetting permissions..."
tccutil reset Accessibility co.itbeaver.ru-wisper 2>/dev/null || true

echo ""
echo "RuWisper has been completely uninstalled."
