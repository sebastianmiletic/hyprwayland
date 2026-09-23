#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
BUILD="$ROOT/.build-release"
OUT="$ROOT/dist/release-$VERSION"
rm -rf "$BUILD" "$OUT"
mkdir -p "$OUT"

swift build -c release --arch arm64 --arch x86_64 --build-path "$BUILD"
UNIVERSAL_BIN="$BUILD/out/Products/Release/Ryft"
RESOURCE_BUNDLE="$BUILD/out/Products/Release/Ryft_Ryft.bundle"
SIGNING_IDENTITY="${RYFT_SIGNING_IDENTITY:-Termatica Release Signing}"

make_app() {
  local label="$1" arch="$2"
  local app="$OUT/Ryft-$label.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  if [[ "$arch" == universal ]]; then cp "$UNIVERSAL_BIN" "$app/Contents/MacOS/Ryft"; else lipo "$UNIVERSAL_BIN" -thin "$arch" -output "$app/Contents/MacOS/Ryft"; fi
  cp -R "$RESOURCE_BUNDLE" "$app/Contents/Resources/Ryft_Ryft.bundle"
  cp Info.plist "$app/Contents/Info.plist"
  cp Assets/Ryft.icns "$app/Contents/Resources/Ryft.icns"
  chmod +x "$app/Contents/MacOS/Ryft"
  if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$app"
  else
    codesign --force --deep --sign - "$app"
  fi
  codesign --verify --deep --strict "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$OUT/Ryft-$VERSION-$label.zip"
  shasum -a 256 "$OUT/Ryft-$VERSION-$label.zip" >> "$OUT/SHA256SUMS.txt"
}

make_app apple-silicon arm64
make_app intel x86_64
make_app universal universal
printf 'Release artifacts: %s\n' "$OUT"
