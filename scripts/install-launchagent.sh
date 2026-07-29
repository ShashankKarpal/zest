#!/bin/bash
# Installs a LaunchAgent so Zest starts at login and relaunches if it is ever quit or crashes
# (KeepAlive), the same always-on pattern as the other agents on this Mac. Paths are derived
# at runtime, so nothing machine-specific is baked in. Personal use.
set -euo pipefail

LABEL="com.zest.app"
APP_BIN="$HOME/Projects/zest/Zest.app/Contents/MacOS/Zest"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$APP_BIN" ]; then
  echo "Zest.app is not built yet. Run ./build.sh release first, then re-run this."
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

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded $LABEL."
echo "Zest now starts at login and relaunches within seconds if it ever quits."
echo "To stop it deliberately: launchctl unload \"$PLIST\""
echo "The single-instance lock means this never creates a duplicate menu bar icon."
