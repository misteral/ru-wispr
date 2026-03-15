#!/bin/bash
set -euo pipefail

echo "Uninstalling RuWisper..."

echo "  Stopping service..."
brew services stop ru-wisper 2>/dev/null || true

echo "  Removing formula..."
brew uninstall ru-wisper 2>/dev/null || true

echo "  Removing tap..."
brew untap human37/ru-wisper 2>/dev/null || true

echo "  Removing config and model..."
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
