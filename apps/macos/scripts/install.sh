#!/bin/bash
set -euo pipefail

cat <<'EOF'
The Homebrew installer has been removed.

Install Dikto by downloading the latest DMG from:
https://github.com/misteral/dikto/releases/latest

Then:
1. Open the DMG
2. Drag Dikto.app to Applications
3. Launch Dikto from Applications

See docs/install-guide.md for the full setup guide.
EOF

exit 1
