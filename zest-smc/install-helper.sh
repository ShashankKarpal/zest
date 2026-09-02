#!/bin/bash
# Installs the zest-smc helper to a root-owned path and grants passwordless invocation for
# it plus powermetrics. Run as root (via the macOS admin prompt or `sudo bash`). Safe: it
# validates the sudoers file in a temp location before installing it, so a syntax error can
# never break sudo. No paths or usernames are hardcoded; everything is derived at runtime.
set -e

# The real user, even when invoked through sudo / the admin prompt.
USER_NAME="${SUDO_USER:-$(stat -f%Su /dev/console)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILT_HELPER="$SCRIPT_DIR/zest-smc"
DEST_DIR="/usr/local/libexec/zest"
DEST="$DEST_DIR/zest-smc"

if [ "$(id -u)" != "0" ]; then echo "must run as root"; exit 1; fi
if [ ! -x "$BUILT_HELPER" ]; then echo "built helper not found at $BUILT_HELPER (run build.sh first)"; exit 1; fi

# sudoers matches the command by path string, not by inode. If any parent of
# the destination is writable by a non-root user (Intel Homebrew chowns
# /usr/local to the user), that user could swap in their own binary at the
# granted path and run it as root without a password. Refuse rather than grant.
for d in /usr/local /usr/local/libexec "$DEST_DIR"; do
  if [ -e "$d" ] && [ "$(stat -f%u "$d")" != "0" ]; then
    echo "REFUSED: $d is not owned by root (uid $(stat -f%u "$d")); a sudoers grant on a path under it would be hijackable"
    exit 1
  fi
done

install -d -o root -g wheel -m 755 "$DEST_DIR"
install -o root -g wheel -m 755 "$BUILT_HELPER" "$DEST"

# The powermetrics grant is pinned to the exact argument vector Zest uses
# (Sources/Zest/Energy/EnergySampler.swift). An unrestricted grant would let
# any process running as the user run `powermetrics -o <path>` as root, which
# creates or truncates arbitrary files (audit 2026-09-02).
TMP="$(mktemp)"
cat > "$TMP" <<EOF
$USER_NAME ALL=(root) NOPASSWD: $DEST
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/powermetrics --samplers tasks -n 1 -i 400
EOF

if visudo -cf "$TMP" >/dev/null 2>&1; then
  install -o root -g wheel -m 440 "$TMP" /etc/sudoers.d/zest-smc
  rm -f "$TMP"
  echo "INSTALL_OK helper=$DEST sudoers=/etc/sudoers.d/zest-smc user=$USER_NAME"
else
  rm -f "$TMP"
  echo "SUDOERS_INVALID: not installed"
  exit 1
fi
