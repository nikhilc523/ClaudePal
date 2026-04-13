#!/bin/bash
# Build and run ClaudePalMac via xcodebuild.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="$PKG_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/ClaudePalMac.app"

cd "$PKG_DIR"

echo "Building..."
xcodebuild -project ClaudePalMac.xcodeproj \
    -scheme ClaudePalMac \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | grep -E '(BUILD|error:|warning:)' || true

if [ ! -d "$APP_PATH" ]; then
    echo "Build failed — app bundle not found."
    exit 1
fi

echo "Launching ClaudePal..."
open "$APP_PATH"
