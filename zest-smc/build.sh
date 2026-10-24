#!/bin/bash
# Builds the zest-smc helper. Command Line Tools only.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
swiftc -O "$DIR/main.swift" -o "$DIR/zest-smc"
echo "Built $DIR/zest-smc"
echo
echo "To enable the Low Power Mode helper, install it once (RISKY class: review first):"
echo
echo "  sudo /bin/bash \"$DIR/install-helper.sh\""
echo
echo "That copies the helper to /usr/local/libexec/zest and adds a validated sudoers entry for"
echo "exactly four commands: the helper's probe, lowpowermode 0, lowpowermode 1, and one"
echo "powermetrics argument vector. Preview it with: bash \"$DIR/install-helper.sh\" --print-sudoers \"\$USER\""
echo "Until then, Zest never invokes the helper and the related controls stay locked."
