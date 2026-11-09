#!/bin/bash
#
# Shared helpers for the build scripts in this directory. Sourced, never run
# directly.
#
# Signing is detected rather than hardcoded: project.yml pins the maintainer's
# Developer ID/team, which exists on exactly one machine. These scripts pass
# whatever identity *this* keychain actually holds, so `Scripts/build.sh` works
# on a fresh clone with an Apple ID, an Apple Developer account, or no account
# at all (ad-hoc).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Codenotch.xcodeproj"
SCHEME="Codenotch"
APP_NAME="Codenotch"
DERIVED="build/DerivedData"

# Use the full toolchain when it is installed. Exporting a path that is not
# there breaks every xcodebuild invocation, so only do it when it exists.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "This file is sourced by the other scripts in Scripts/ — run one of those instead." >&2
  exit 1
fi

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' is missing — install it with: brew install $2" >&2
    exit 1
  fi
}

# Sets SIGN_IDENTITY, SIGN_TEAM and SIGN_STYLE. Developer ID is preferred
# because it is what a distributable build needs; Apple Development next
# because it is stable, so a keychain "Always Allow" grant survives rebuilds;
# ad-hoc last because it needs no Apple account at all.
detect_signing() {
  local listing full team

  listing=$(security find-identity -v -p codesigning 2>/dev/null || true)

  if printf '%s\n' "$listing" | grep -q '"Developer ID Application'; then
    SIGN_IDENTITY="Developer ID Application"
  elif printf '%s\n' "$listing" | grep -q '"Apple Development'; then
    SIGN_IDENTITY="Apple Development"
  else
    SIGN_IDENTITY="-"
    SIGN_TEAM=""
    SIGN_STYLE=Automatic
    return
  fi

  # The full certificate name, including the account suffix, as codesign
  # resolves it. The team is the subject's OU — not the bracketed value in the
  # CN, which is the developer's id and only coincides on some accounts.
  full=$(printf '%s\n' "$listing" \
    | sed -n "s/.*\"\\($SIGN_IDENTITY[^\"]*\\)\".*/\\1/p" | head -1)
  team=$(security find-certificate -c "$full" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt sep_multiline 2>/dev/null \
    | sed -n 's/^ *OU=\([A-Z0-9]*\)$/\1/p' | head -1)

  if [ -z "$team" ]; then
    echo "warning: no team ID found for \"$full\" — falling back to ad-hoc signing." >&2
    SIGN_IDENTITY="-"
    SIGN_TEAM=""
    SIGN_STYLE=Automatic
    return
  fi

  SIGN_TEAM="$team"
  SIGN_STYLE=Manual
}

# project.yml is the source of truth; the .xcodeproj is generated and ignored.
generate_project() {
  require xcodegen xcodegen
  xcodegen generate >/dev/null
  mkdir -p "$PROJECT/project.xcworkspace/xcshareddata/swiftpm"
  cp Package.resolved "$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}

app_path() {
  echo "$ROOT/$DERIVED/Build/Products/$1/$APP_NAME.app"
}

build_app() {
  local config="$1" who
  generate_project
  detect_signing

  mkdir -p build
  # Stops Spotlight indexing build output as installed applications, which
  # otherwise leaves spare "Codenotch" entries in app search.
  touch build/.metadata_never_index

  who="$SIGN_IDENTITY"
  [ "$SIGN_IDENTITY" = "-" ] && who="ad-hoc identity"
  echo "==> $APP_NAME $config — signing with $who${SIGN_TEAM:+ (team $SIGN_TEAM)}"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$config" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED" \
    "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" \
    "CODE_SIGN_STYLE=$SIGN_STYLE" \
    "DEVELOPMENT_TEAM=$SIGN_TEAM" \
    "PROVISIONING_PROFILE_SPECIFIER=" \
    build
}
