#!/bin/bash
#
# Build Release and package a drag-to-Applications disk image for sharing.
#
#   Scripts/dist.sh
#
# Output: build/dist/Codenotch-<version>.dmg
#
# This is a local build, not the notarized release: a copy downloaded from
# another machine is quarantined by macOS. That only affects sharing the file;
# installing it on this Mac needs nothing extra.

set -euo pipefail
source "$(dirname "$0")/common.sh"

require create-dmg create-dmg

build_app Release
APP=$(app_path Release)
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)
OUT="$ROOT/build/dist"
DMG="$OUT/$APP_NAME-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT/stage"
ditto "$APP" "$OUT/stage/$APP_NAME.app"

create-dmg \
  --volname "$APP_NAME" \
  --window-pos 400 300 \
  --window-size 604 404 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "$APP_NAME.app" \
  --background "$ROOT/docs/design/dmg-background.png" \
  --skip-jenkins \
  "$DMG" "$OUT/stage"

rm -rf "$OUT/stage"
echo
echo "Disk image: $DMG"
