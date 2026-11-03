#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-app.sh" release
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Info.plist")
DIST="$ROOT/dist"
mkdir -p "$DIST"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT/build/StatusForecast.app" "$STAGE/StatusForecast.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/StatusForecast-${VERSION}-arm64.dmg"
hdiutil create -volname StatusForecast -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
cd "$DIST"
shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt
echo "Built $DMG"
