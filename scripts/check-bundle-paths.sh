#!/bin/bash
# check-bundle-paths.sh: fails when a built bundle carries a home folder path or the
# builder's macOS username (finding F04: the v3.0 zip carried 76 build paths of the form
# /Users/<name>/...). build.sh runs it on every release build.
#
#   bash scripts/check-bundle-paths.sh <Zest.app or any folder>
#
# It greps the raw bytes of every regular file. `strings -a | grep /Users/` is not a valid
# check: on macOS 27 it printed 0 for a binary holding 87 such paths, because they sit in
# the debug symbol table. The username is matched as a whole path component ("/<name>/"),
# never as a bare word: a short login such as "dev" or the CI runner's "runner" also occurs
# in ordinary type names. A login that is itself a macOS system folder name (usr, bin,
# private, System...) cannot be told apart from /usr/bin/pmset and the like, so for those
# only /Users/ is checked, and the verdict line says so.
# Exit: 0 clean, 1 a path or the username was found, 2 usage error, nothing to read, or a
# file that could not be read.
set -euo pipefail
TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "usage: bash scripts/check-bundle-paths.sh <bundle or folder>" >&2
  exit 2
fi
ME="$(id -un)"
case "$ME" in
  usr|bin|sbin|etc|var|tmp|opt|dev|cores|private|System|Library|Applications|Volumes|Users)
    NAME_PAT=""; NAME_NOTE="user name not checked: it is a system folder name" ;;
  *) NAME_PAT="/$ME/"; NAME_NOTE="0 hits for /<build user>/" ;;
esac

files=0
bytes=0
hits=0
while IFS= read -r -d '' f; do
  if [ ! -r "$f" ]; then echo "PATH CHECK: cannot read ${f#"$TARGET"/}" >&2; exit 2; fi
  files=$((files + 1))
  bytes=$((bytes + $(stat -f%z "$f")))
  # One pass per file; grep exits 1 on no match (a count of 0), 2 or more on a read error.
  rc=0
  if [ -n "$NAME_PAT" ]; then
    matches="$(LC_ALL=C grep -a -o -F -e /Users/ -e "$NAME_PAT" -- "$f")" || rc=$?
  else
    matches="$(LC_ALL=C grep -a -o -F -e /Users/ -- "$f")" || rc=$?
  fi
  if [ "$rc" -gt 1 ]; then
    echo "PATH CHECK: grep failed (exit $rc) on ${f#"$TARGET"/}" >&2
    exit 2
  fi
  if [ -n "$matches" ]; then
    n="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
    hits=$((hits + n))
    echo "  $n hits in ${f#"$TARGET"/} (a home folder path or the build user's name as a folder)" >&2
  fi
done < <(find "$TARGET" -type f -print0)

if [ "$files" = 0 ]; then echo "PATH CHECK: no files read in $TARGET" >&2; exit 2; fi
if [ "$hits" != 0 ]; then
  echo "PATH CHECK FAILED: $hits hits in $files files ($bytes bytes read)" >&2
  exit 1
fi
echo "PATH CHECK OK: $files files, $bytes bytes read, 0 hits for /Users/, $NAME_NOTE"
