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
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"
