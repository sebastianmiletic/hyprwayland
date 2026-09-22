#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
APP="$ROOT/dist/Waycode.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Waycode "$APP/Contents/MacOS/Waycode"
cp -R .build/release/Waycode_Waycode.bundle "$APP/Contents/Resources/Waycode_Waycode.bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/Waycode.icns "$APP/Contents/Resources/Waycode.icns"
chmod +x "$APP/Contents/MacOS/Waycode"
# A stable identity keeps macOS TCC grants attached across local updates. An
# ad-hoc signature changes its code requirement every build and can cause
# Accessibility and Automation to appear to be requested again.
SIGNING_IDENTITY="${WAYCODE_SIGNING_IDENTITY:-Termatica Release Signing}"
if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "warning: '$SIGNING_IDENTITY' unavailable; using an ad-hoc signature" >&2
  codesign --force --deep --sign - "$APP"
fi
printf 'Built %s\n' "$APP"
