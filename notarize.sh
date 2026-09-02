#!/bin/bash
# notarize.sh: notarize and staple Zest.app, then produce a distributable zip.
# Requires: ./build.sh release already run, and a notarytool keychain profile
# (default name "notary", created once with: xcrun notarytool store-credentials).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP="$ROOT/Zest.app"
PROFILE="${ZEST_NOTARY_PROFILE:-notary}"

if [ ! -d "$APP" ]; then
  echo "Zest.app not found. Run ./build.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$(mktemp -d -t zest-notarize)/Zest-notarize.zip"   # unpredictable path, not a fixed /tmp name
DIST="$ROOT/Zest-v${VERSION}-macOS.zip"

echo "==> Zipping for submission"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Submitting to the Apple notary service (can take a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"

echo "==> Gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Building distributable zip"
rm -f "$DIST"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST"
echo "==> Done: $DIST"
