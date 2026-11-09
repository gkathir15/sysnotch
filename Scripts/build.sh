#!/bin/bash
#
# Build the app with the signing identity available on this Mac.
#
#   Scripts/build.sh            # Debug
#   Scripts/build.sh release    # Release
#
# The .app lands in build/DerivedData/Build/Products/<config>/Codenotch.app.

set -euo pipefail
source "$(dirname "$0")/common.sh"

case "${1:-debug}" in
  debug|Debug|--debug)   CONFIG=Debug ;;
  release|Release|--release) CONFIG=Release ;;
  -h|--help)
    echo "usage: $0 [debug|release]"
    echo
    echo "  debug    Debug build (default)"
    echo "  release  Release build"
    echo
    echo "Signs with the Developer ID, Apple Development, or ad-hoc identity"
    echo "found in this Mac's keychain."
    exit 0
    ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

build_app "$CONFIG"
echo
echo "Built: $(app_path "$CONFIG")"
