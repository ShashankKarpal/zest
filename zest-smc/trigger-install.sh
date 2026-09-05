#!/bin/bash
# Pops the macOS admin password dialog and runs install-helper.sh as root. Logs the result
# to a mktemp file and prints its path. Launched detached so nothing blocks; the dialog
# waits for you to authenticate. Paths are derived at runtime, so no username is hardcoded.
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$(mktemp -t zest-install)"   # unpredictable path: /tmp/<fixed name> could be symlink-planted
osascript -e "do shell script \"/bin/bash '$DIR/install-helper.sh'\" with administrator privileges with prompt \"Zest needs your password once to install the Low Power Mode and per-app energy helper.\"" > "$LOG" 2>&1
echo "exit=$?" >> "$LOG"
echo "log: $LOG"
