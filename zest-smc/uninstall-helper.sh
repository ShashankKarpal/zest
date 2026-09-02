#!/bin/bash
# Removes everything install-helper.sh put on the system: the sudoers grant and
# the root-owned helper binary. Run with sudo. Safe to run twice.
set -e
if [ "$(id -u)" != "0" ]; then echo "run with sudo: sudo bash $0"; exit 1; fi
rm -f /etc/sudoers.d/zest-smc
rm -rf /usr/local/libexec/zest
echo "UNINSTALL_OK removed /etc/sudoers.d/zest-smc and /usr/local/libexec/zest"
