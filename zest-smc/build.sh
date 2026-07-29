#!/bin/bash
# Builds the zest-smc helper. Command Line Tools only.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
swiftc -O "$DIR/main.swift" -o "$DIR/zest-smc"
echo "Built $DIR/zest-smc"
echo
echo "To enable the charge and Low Power Mode helper, install it once (RISKY class: review first):"
echo
echo "  sudo /bin/bash \"$DIR/install-helper.sh\""
echo
echo "That copies the helper to /usr/local/libexec/zest and adds one validated sudoers line."
echo "Until then, Zest never invokes the helper and the related controls stay locked."
