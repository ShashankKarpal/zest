#!/bin/bash
# Removes the com.zest.app LaunchAgent installed by install-launchagent.sh.
# Without this, deleting Zest.app leaves a KeepAlive job relaunching a missing
# binary every few seconds, forever. Does not touch the app or its data.
set -euo pipefail
LABEL="com.zest.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Removed $LABEL. Zest no longer starts at login."
echo "To remove the root helper and sudoers grant too: sudo bash zest-smc/uninstall-helper.sh"
echo "App data lives in ~/Library/Application Support/Zest (delete it yourself if you want a clean slate)."
