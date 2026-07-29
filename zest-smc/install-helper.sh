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

install -d -o root -g wheel -m 755 "$DEST_DIR"
install -o root -g wheel -m 755 "$BUILT_HELPER" "$DEST"

TMP="$(mktemp)"
cat > "$TMP" <<EOF
$USER_NAME ALL=(root) NOPASSWD: $DEST
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/powermetrics
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
