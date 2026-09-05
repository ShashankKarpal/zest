#!/bin/bash
# Installs a LaunchAgent so Zest starts at login and relaunches if it is ever quit or crashes
# (KeepAlive), the same always-on pattern as the other agents on this Mac. Paths are derived
# at runtime, so nothing machine-specific is baked in. Personal use.
#
# Which bundle: ZEST_APP if set; else ~/Applications/Zest.app when `bash build.sh install`
# has put one there; else the in-tree build beside this repo. Prefer the installed copy:
# build.sh deletes and rebuilds the in-tree bundle, which would take a running agent's
# program away from under it.
set -euo pipefail

LABEL="com.zest.app"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "${ZEST_APP:-}" ]; then
  APP="$ZEST_APP"
elif [ -d "$HOME/Applications/Zest.app" ]; then
  APP="$HOME/Applications/Zest.app"
else
  APP="$REPO/Zest.app"
fi
APP_BIN="$APP/Contents/MacOS/Zest"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$APP_BIN" ]; then
  echo "No Zest.app at $APP. Run 'bash build.sh release install' first, then re-run this."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

# bootout then bootstrap: launchd pins the program's code identity at bootstrap, so a
# plain reload after a rebuild fails with OS_REASON_CODESIGNING.
if launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null; then sleep 1; fi
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Loaded $LABEL -> $APP_BIN"
echo "Zest now starts at login and relaunches within seconds if it ever quits."
echo "To stop it deliberately: bash scripts/uninstall-launchagent.sh"
echo "The single-instance lock means this never creates a duplicate menu bar icon."
