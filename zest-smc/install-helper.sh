#!/bin/bash
# Installs the zest-smc helper to a root-owned path and grants passwordless invocation of
# the exact commands Zest sends: the helper's `probe` and `lowpowermode 0|1`, and
# powermetrics with one fixed argument vector. Run as root (via the macOS admin prompt or
# `sudo bash`). Safe: it validates the sudoers file in a temp location before installing it,
# so a syntax error can never break sudo. No paths or usernames are hardcoded; everything is
# derived at runtime.
#
#   bash install-helper.sh --print-sudoers <user>   prints the grant it would install and
#                                                    checks it with visudo; no root needed
set -e

# The real user, even when invoked through sudo / the admin prompt.
USER_NAME="${SUDO_USER:-$(stat -f%Su /dev/console)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILT_HELPER="$SCRIPT_DIR/zest-smc"
DEST_DIR="/usr/local/libexec/zest"
DEST="$DEST_DIR/zest-smc"

# One line per argument vector. sudoers matches a command with arguments exactly, so the
# helper can be run as root only as `probe`, `lowpowermode 0` or `lowpowermode 1`; a bare
# path would allow any arguments, the SMC write earlier builds carried included. The
# powermetrics line is pinned to the vector in Sources/Zest/Energy/EnergySampler.swift: an
# unrestricted grant would let any process running as the user run `powermetrics -o <path>`
# as root, which creates or truncates arbitrary files (audit 2026-09-02).
sudoers_lines() {
  cat <<EOF
$1 ALL=(root) NOPASSWD: $DEST probe
$1 ALL=(root) NOPASSWD: $DEST lowpowermode 0
$1 ALL=(root) NOPASSWD: $DEST lowpowermode 1
$1 ALL=(root) NOPASSWD: /usr/bin/powermetrics --samplers tasks -n 1 -i 400
EOF
}

# A macOS short name: letters, digits, dot, underscore, hyphen. Anything else (a space, a
# newline) could change the meaning of the sudoers file, so refuse it.
valid_user() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' && [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = 0 ]; }

if [ "${1:-}" = "--print-sudoers" ]; then
  [ -n "${2:-}" ] || { echo "usage: bash install-helper.sh --print-sudoers <user>" >&2; exit 2; }
  valid_user "$2" || { echo "INVALID_USER: not a macOS short name" >&2; exit 2; }
  CHECK="$(mktemp)"
  sudoers_lines "$2" | tee "$CHECK"
  visudo -cf "$CHECK" >/dev/null || { rm -f "$CHECK"; echo "SUDOERS_INVALID" >&2; exit 1; }
  rm -f "$CHECK"
  exit 0
fi

if [ "$(id -u)" != "0" ]; then echo "must run as root"; exit 1; fi
valid_user "$USER_NAME" || { echo "INVALID_USER: not a macOS short name"; exit 1; }
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

# Validate the grant, then install it BEFORE the helper: the app trusts the helper's
# interface number to mean the matching grant is installed, so a new binary must never sit
# behind an old grant. If a step fails part way, the narrow grant sits beside the old
# binary instead, which answers without a number and is reported as outdated.
TMP="$(mktemp)"
sudoers_lines "$USER_NAME" > "$TMP"
if ! visudo -cf "$TMP" >/dev/null 2>&1; then
  rm -f "$TMP"
  echo "SUDOERS_INVALID: nothing installed"
  exit 1
fi

install -o root -g wheel -m 440 "$TMP" /etc/sudoers.d/zest-smc
rm -f "$TMP"
install -d -o root -g wheel -m 755 "$DEST_DIR"
install -o root -g wheel -m 755 "$BUILT_HELPER" "$DEST"
echo "INSTALL_OK helper=$DEST sudoers=/etc/sudoers.d/zest-smc user=$USER_NAME"
