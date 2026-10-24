#!/bin/bash
# check-bundle-paths.sh: fails when a built bundle carries a home folder path or the
# builder's macOS username (finding F04: the v3.0 zip carried 76 build paths of the form
# /Users/<name>/...). build.sh runs it on every release build.
#
#   bash scripts/check-bundle-paths.sh <Zest.app or any folder>
#
# It greps the raw bytes of every regular file. `strings -a | grep /Users/` is not a valid
# check: on macOS 27 it printed 0 for a binary holding 87 such paths, because they sit in
# the debug symbol table. The username check is skipped when CI=true (the GitHub runner's
# user is "runner", a word that legitimately appears in type names); /Users/ still covers
# the runner's home path there.
# Exit: 0 clean, 1 a path or the username was found, 2 usage error or nothing to read.
set -euo pipefail
TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "usage: bash scripts/check-bundle-paths.sh <bundle or folder>" >&2
  exit 2
fi
WORDS=("/Users/")
USER_NOTE="username checked"
if [ "${CI:-}" = "true" ]; then USER_NOTE="username skipped (CI)"
else WORDS+=("$(id -un)"); fi

files=0
bytes=0
hits=0
while IFS= read -r -d '' f; do
  if [ ! -r "$f" ]; then echo "PATH CHECK: cannot read ${f#"$TARGET"/}" >&2; exit 2; fi
  files=$((files + 1))
  bytes=$((bytes + $(stat -f%z "$f")))
  for w in "${WORDS[@]}"; do
    # grep exits 1 on no match; that is a count of 0, not an error.
    n="$({ LC_ALL=C grep -a -o -F -- "$w" "$f" || [ $? = 1 ]; } | wc -l | tr -d ' ')"
    if [ "$n" != "0" ]; then
      hits=$((hits + n))
      if [ "$w" = "/Users/" ]; then echo "  $n x /Users/ in ${f#"$TARGET"/}" >&2
      else echo "  $n x the build user's name in ${f#"$TARGET"/}" >&2; fi
    fi
  done
done < <(find "$TARGET" -type f -print0)

if [ "$files" = 0 ]; then echo "PATH CHECK: no files read in $TARGET" >&2; exit 2; fi
if [ "$hits" != 0 ]; then
  echo "PATH CHECK FAILED: $hits hits in $files files ($bytes bytes read, $USER_NOTE)" >&2
  exit 1
fi
echo "PATH CHECK OK: $files files, $bytes bytes read, 0 hits ($USER_NOTE)"
