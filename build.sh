#!/bin/bash
# Build open-wispr with MLX Metal support
# Uses xcodebuild to compile Metal shaders, then swift build for the binary

set -e

echo "Building with xcodebuild (compiles Metal shaders)..."
xcodebuild -scheme open-wispr -configuration Release -destination "platform=macOS" build -quiet 2>/dev/null

# Find the metallib bundle from xcodebuild
DERIVED_DATA=$(find ~/Library/Developer/Xcode/DerivedData/open-wispr-*/Build/Products/Release -name "mlx-swift_Cmlx.bundle" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$DERIVED_DATA" ]; then
    echo "Error: Could not find metallib bundle. Run xcodebuild first."
    exit 1
fi

echo "Building with swift build (release)..."
swift build -c release 2>&1 | tail -3

# Copy metallib bundle next to the binary
cp -R "$DERIVED_DATA" .build/release/
echo "Copied Metal library bundle"

# Copy the binary to a convenient location
BINARY=.build/release/open-wispr
echo ""
echo "Build complete: $BINARY"
echo "Run: $BINARY status"
echo "Run: $BINARY start"
