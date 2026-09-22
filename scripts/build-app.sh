#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
APP="$ROOT/dist/Hyprshell.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hyprshell "$APP/Contents/MacOS/Hyprshell"
cp -R .build/release/Hyprshell_Hyprshell.bundle "$APP/Contents/Resources/Hyprshell_Hyprshell.bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/Hyprshell.icns "$APP/Contents/Resources/Hyprshell.icns"
chmod +x "$APP/Contents/MacOS/Hyprshell"
# A stable identity keeps macOS TCC grants attached across local updates. An
# ad-hoc signature changes its code requirement every build and can cause
# Accessibility and Automation to appear to be requested again.
SIGNING_IDENTITY="${HYPRSHELL_SIGNING_IDENTITY:-Termatica Release Signing}"
if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "warning: '$SIGNING_IDENTITY' unavailable; using an ad-hoc signature" >&2
  codesign --force --deep --sign - "$APP"
fi
printf 'Built %s\n' "$APP"
