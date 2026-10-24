#!/bin/bash
# test-bundle-paths.sh: checks scripts/check-bundle-paths.sh on planted fixtures, so a
# check that silently reads nothing cannot pass. Run by CI. Exit 0 when every case passes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${ZEST_PATH_CHECK:-$HERE/check-bundle-paths.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
checks=0

# case <name> <want exit> <CI value> <folder>
case_() {
  local name="$1" want="$2" ci="$3" dir="$4" rc=0
  CI="$ci" bash "$CHECK" "$dir" >/dev/null 2>&1 || rc=$?
  checks=$((checks + 1))
  if [ "$rc" = "$want" ]; then echo "ok   $name"
  else fails=$((fails + 1)); echo "FAIL $name (exit $rc, want $want)"; fi
}

mkdir -p "$TMP/clean/Contents/MacOS"
printf 'plain text, no paths\n' > "$TMP/clean/Contents/Info.plist"
printf '\x00\x01binary\x00runner\x00' > "$TMP/clean/Contents/MacOS/Zest"
case_ "clean bundle passes" 0 "" "$TMP/clean"
case_ "clean bundle passes on CI" 0 true "$TMP/clean"

mkdir -p "$TMP/path/Contents/MacOS"
# The v3.0 shape: a path inside binary bytes, between NULs, with no newline anywhere.
printf '\x00\x01\x02/Users/someone/Projects/zest/Sources/Zest/\x00\x03' > "$TMP/path/Contents/MacOS/Zest"
case_ "home path in binary bytes fails" 1 "" "$TMP/path"
case_ "home path fails on CI too" 1 true "$TMP/path"

mkdir -p "$TMP/user/Contents/Resources"
printf '\x00%s\x00' "$(id -un)" > "$TMP/user/Contents/Resources/blob"
case_ "build user's name fails" 1 "" "$TMP/user"
case_ "build user's name is skipped on CI" 0 true "$TMP/user"

mkdir -p "$TMP/empty"
case_ "empty folder is an error, not a pass" 2 "" "$TMP/empty"
case_ "missing folder is an error" 2 "" "$TMP/nope"

mkdir -p "$TMP/locked"
printf '/Users/someone/' > "$TMP/locked/f"
chmod 000 "$TMP/locked/f"
case_ "unreadable file is an error, not a pass" 2 "" "$TMP/locked"
chmod 600 "$TMP/locked/f"

echo "test-bundle-paths: $checks checks, $fails failed"
[ "$fails" = 0 ]
