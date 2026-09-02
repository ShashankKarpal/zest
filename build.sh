#!/bin/bash
# build.sh: compile the Zest SwiftPM executable and assemble Zest.app.
# Command Line Tools only, no Xcode project.
# Signing: Developer ID with hardened runtime when ZEST_SIGN_IDENTITY is set,
# the config is release, and that identity is in the keychain; ad hoc
# otherwise. There is no default identity (CHANGELOG, Unreleased).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/Zest.app"
BIN_NAME="Zest"
IDENTITY="${ZEST_SIGN_IDENTITY:-}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
if [ ! -f "$BIN_PATH" ]; then
  echo "Build produced no binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon is generated from the design system at build time; the repository
# holds PNGs, never a binary icon blob.
ICONSET_SRC="$ROOT/design/app-icons/macos/AppIcon.appiconset"
if [ -d "$ICONSET_SRC" ]; then
  echo "==> Building AppIcon.icns from design/app-icons"
  TMPICON="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$TMPICON"
  cp "$ICONSET_SRC"/icon_*.png "$TMPICON/"
  iconutil -c icns "$TMPICON" -o "$APP/Contents/Resources/AppIcon.icns" \
    || echo "   (icns generation skipped)"
fi

if [ "$CONFIG" = "release" ] && [ -n "$IDENTITY" ] && security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "==> Codesign: Developer ID, hardened runtime"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> Codesign: ad hoc (set ZEST_SIGN_IDENTITY for a Developer ID build)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (codesign skipped)"
fi

echo "==> Done: $APP"
