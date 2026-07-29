#!/bin/bash
# Pops the macOS admin password dialog and runs install-helper.sh as root. Logs the result
# to /tmp/zest-install.log. Launched detached so nothing blocks; the dialog waits for you to
# authenticate. Paths are derived at runtime, so no username is hardcoded.
DIR="$(cd "$(dirname "$0")" && pwd)"
osascript -e "do shell script \"/bin/bash '$DIR/install-helper.sh'\" with administrator privileges with prompt \"Zest needs your password once to enable the charge and Low Power Mode helper.\"" > /tmp/zest-install.log 2>&1
echo "exit=$?" >> /tmp/zest-install.log
