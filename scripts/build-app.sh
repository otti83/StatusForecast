#!/usr/bin/env bash
# StatusForecast — build a .app bundle from the SwiftPM executable.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="StatusForecast"
BUNDLE_ID="com.statusforecast.app"
APP_DIR="$ROOT/build/${APP_NAME}.app"

cd "$ROOT"

echo "▶ swift build --configuration $CONFIG"
swift build --configuration "$CONFIG" --arch arm64

BIN_DIR="$(swift build --configuration "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"

# SwiftPM places resource bundles next to the binary.
RES_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Ad-hoc sign so macOS keeps it persistent across reboots.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "✓ Built $APP_DIR"
echo "  open $APP_DIR  # to launch"
