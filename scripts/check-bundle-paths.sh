#!/bin/bash
# check-bundle-paths.sh: fails when a built bundle carries a home folder path or the
# builder's macOS username (finding F04: the v3.0 zip carried 76 build paths of the form
# /Users/<name>/...). build.sh runs it on every release build.
#
#   bash scripts/check-bundle-paths.sh <Zest.app or any folder>
#
# It greps the raw bytes of every regular file. `strings -a | grep /Users/` is not a valid
# check: on macOS 27 it printed 0 for a binary holding 87 such paths, because they sit in
# the debug symbol table. The username is matched as a path component ("/<name>"), never
# as a bare word: a short login such as "dev" or the CI runner's "runner" also occurs in
# ordinary type names, and a bare match would fail every build for those users.
# Exit: 0 clean, 1 a path or the username was found, 2 usage error, nothing to read, or a
# file that could not be read.
set -euo pipefail
TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "usage: bash scripts/check-bundle-paths.sh <bundle or folder>" >&2
  exit 2
fi
WORDS=("/Users/" "/$(id -un)")

files=0
bytes=0
hits=0
while IFS= read -r -d '' f; do
  if [ ! -r "$f" ]; then echo "PATH CHECK: cannot read ${f#"$TARGET"/}" >&2; exit 2; fi
  files=$((files + 1))
  bytes=$((bytes + $(stat -f%z "$f")))
  for w in "${WORDS[@]}"; do
    # grep exits 1 on no match, which is a count of 0; 2 or more is a read error.
    rc=0
    matches="$(LC_ALL=C grep -a -o -F -- "$w" "$f")" || rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "PATH CHECK: grep failed (exit $rc) on ${f#"$TARGET"/}" >&2
      exit 2
    fi
    n=0
    if [ -n "$matches" ]; then n="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"; fi
    if [ "$n" != "0" ]; then
      hits=$((hits + n))
      if [ "$w" = "/Users/" ]; then echo "  $n x /Users/ in ${f#"$TARGET"/}" >&2
      else echo "  $n x the build user's name as a path part in ${f#"$TARGET"/}" >&2; fi
    fi
  done
done < <(find "$TARGET" -type f -print0)

if [ "$files" = 0 ]; then echo "PATH CHECK: no files read in $TARGET" >&2; exit 2; fi
if [ "$hits" != 0 ]; then
  echo "PATH CHECK FAILED: $hits hits in $files files ($bytes bytes read)" >&2
  exit 1
fi
echo "PATH CHECK OK: $files files, $bytes bytes read, 0 hits for /Users/ or /<build user>"
