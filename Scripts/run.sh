#!/bin/bash
#
# Build a Debug copy and launch it, replacing any instance already running.
#
#   Scripts/run.sh

set -euo pipefail
source "$(dirname "$0")/common.sh"

build_app Debug
APP=$(app_path Debug)

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
open "$APP"

echo
echo "Launched $APP"
