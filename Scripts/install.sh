#!/bin/bash
#
# Build Release and install it into /Applications, then launch it.
#
#   Scripts/install.sh
#
# Locally built apps carry no quarantine flag, so Gatekeeper will not block
# this even when the build is only Apple Development or ad-hoc signed.

set -euo pipefail
source "$(dirname "$0")/common.sh"

build_app Release
APP=$(app_path Release)

# Quit first so the bundle can be replaced in place; ignore "not running".
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/$APP_NAME.app"
ditto "$APP" "/Applications/$APP_NAME.app"
open "/Applications/$APP_NAME.app"

echo
echo "Installed: /Applications/$APP_NAME.app"
