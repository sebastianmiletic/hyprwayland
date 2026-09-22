#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
APP="$ROOT/dist/Ryft.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ryft "$APP/Contents/MacOS/Ryft"
cp -R .build/release/Ryft_Ryft.bundle "$APP/Contents/Resources/Ryft_Ryft.bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/Ryft.icns "$APP/Contents/Resources/Ryft.icns"
chmod +x "$APP/Contents/MacOS/Ryft"
# A stable identity keeps macOS TCC grants attached across local updates. An
# ad-hoc signature changes its code requirement every build and can cause
# Accessibility and Automation to appear to be requested again.
SIGNING_IDENTITY="${RYFT_SIGNING_IDENTITY:-Termatica Release Signing}"
if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "warning: '$SIGNING_IDENTITY' unavailable; using an ad-hoc signature" >&2
  codesign --force --deep --sign - "$APP"
fi
printf 'Built %s\n' "$APP"
