#!/bin/bash
# build.sh: compile the Zest SwiftPM executable and assemble Zest.app.
# Command Line Tools only, no Xcode project.
#
#   bash build.sh [release|debug] [install]
#
# Signing: Developer ID with hardened runtime when ZEST_SIGN_IDENTITY is set,
# the config is release, and that identity is in the keychain; ad hoc
# otherwise. There is no default identity (CHANGELOG, Unreleased).
#
# `install` copies the finished bundle to ZEST_INSTALL_DIR (default
# ~/Applications) with an atomic swap, so the copy a LaunchAgent points at is
# never half-written and never deleted by a rebuild. The in-tree Zest.app is
# a build product only; run scripts/install-launchagent.sh once so launchd
# starts the installed copy, and after every install do
#   launchctl bootout gui/$(id -u)/com.zest.app
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.zest.app.plist
# (launchd pins the program's code identity; kickstart -k fails after a rebuild).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="release"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    release|debug) CONFIG="$arg" ;;
    install) INSTALL=1 ;;
    *) echo "usage: bash build.sh [release|debug] [install]" >&2; exit 2 ;;
  esac
done
APP="$ROOT/Zest.app"
BIN_NAME="Zest"
IDENTITY="${ZEST_SIGN_IDENTITY:-}"
INSTALL_DIR="${ZEST_INSTALL_DIR:-$HOME/Applications}"

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

if [ "$INSTALL" = 1 ]; then
  TARGET="$INSTALL_DIR/Zest.app"
  STAGE="$INSTALL_DIR/.Zest.app.new"
  OLD="$INSTALL_DIR/.Zest.app.old"
  echo "==> Installing to $TARGET"
  mkdir -p "$INSTALL_DIR"
  rm -rf "$STAGE" "$OLD"
  # ditto preserves the signature, resource forks and permissions byte for byte.
  ditto "$APP" "$STAGE"
  codesign --verify --strict "$STAGE"
  if [ -d "$TARGET" ]; then mv "$TARGET" "$OLD"; fi
  mv "$STAGE" "$TARGET"
  rm -rf "$OLD"
  codesign --verify --strict "$TARGET"
  echo "==> Installed: $TARGET"
  if launchctl print "gui/$(id -u)/com.zest.app" >/dev/null 2>&1; then
    echo "    com.zest.app is loaded: bootout then bootstrap it to run this build."
  fi
fi
