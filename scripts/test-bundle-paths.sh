#!/bin/bash
# test-bundle-paths.sh: checks scripts/check-bundle-paths.sh on planted fixtures, so a
# check that silently reads nothing cannot pass. Run by CI. Exit 0 when every case passes.
# ZEST_PATH_CHECK points it at another copy of the check (used for the control run).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${ZEST_PATH_CHECK:-$HERE/check-bundle-paths.sh}"
if [ "$(id -u)" = "0" ]; then echo "run as a normal user: root reads a chmod 000 file" >&2; exit 2; fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
checks=0

# case_ <name> <want exit> <folder> [shim folder put first on PATH]
case_() {
  local name="$1" want="$2" dir="$3" shim="${4:-}" rc=0
  if [ -n "$shim" ]; then PATH="$shim:$PATH" bash "$CHECK" "$dir" >/dev/null 2>&1 || rc=$?
  else bash "$CHECK" "$dir" >/dev/null 2>&1 || rc=$?; fi
  checks=$((checks + 1))
  if [ "$rc" = "$want" ]; then echo "ok   $name"
  else fails=$((fails + 1)); echo "FAIL $name (exit $rc, want $want)"; fi
}

mkdir -p "$TMP/clean/Contents/MacOS"
printf 'plain text, no paths\n' > "$TMP/clean/Contents/Info.plist"
printf '\x00\x01binary\x00runner\x00' > "$TMP/clean/Contents/MacOS/Zest"
case_ "clean bundle passes" 0 "$TMP/clean"

mkdir -p "$TMP/path/Contents/MacOS"
# The v3.0 shape: a path inside binary bytes, between NULs, with no newline anywhere.
printf '\x00\x01\x02/Users/someone/Projects/zest/Sources/Zest/\x00\x03' > "$TMP/path/Contents/MacOS/Zest"
case_ "home path in binary bytes fails" 1 "$TMP/path"

mkdir -p "$TMP/user/Contents/Resources"
printf '\x00/private/var/%s/x\x00' "$(id -un)" > "$TMP/user/Contents/Resources/blob"
case "$(id -un)" in
  usr|bin|sbin|etc|var|tmp|opt|dev|cores|private|System|Library|Applications|Volumes|Users)
    echo "skip build user's name as a folder fails (login is a system folder name)" ;;
  *) case_ "build user's name as a folder fails" 1 "$TMP/user" ;;
esac

mkdir -p "$TMP/bare/Contents/MacOS"
# The name without a following slash: a type name, and a path that only starts with it
# (a login "us" must not match /usr/bin/pmset).
printf '\x00%sPanelType\x00runner\x00/%sx/bin\x00' "$(id -un)" "$(id -un)" > "$TMP/bare/Contents/MacOS/Zest"
case_ "bare user name inside a symbol passes" 0 "$TMP/bare"

mkdir -p "$TMP/empty"
case_ "empty folder is an error, not a pass" 2 "$TMP/empty"
case_ "missing folder is an error" 2 "$TMP/nope"

mkdir -p "$TMP/locked"
printf '/Users/someone/' > "$TMP/locked/f"
chmod 000 "$TMP/locked/f"
case_ "unreadable file is an error, not a pass" 2 "$TMP/locked"
chmod 600 "$TMP/locked/f"

# A grep that fails (exit 2, as on an I/O error) must stop the check with exit 2, not
# look like a clean file (0) or a leak (1).
mkdir -p "$TMP/shim"
printf '#!/bin/sh\nexit 2\n' > "$TMP/shim/grep"
chmod 755 "$TMP/shim/grep"
case_ "grep error is an error, not a pass or a leak" 2 "$TMP/clean" "$TMP/shim"

# A login that is a system folder name ("usr") must not fail on /usr/bin/pmset, while
# /Users/ is still caught for that builder.
mkdir -p "$TMP/idshim" "$TMP/sys/Contents/MacOS" "$TMP/sysleak/Contents/MacOS"
printf '#!/bin/sh\n[ "$1" = "-un" ] && echo usr && exit 0\nexec /usr/bin/id "$@"\n' > "$TMP/idshim/id"
chmod 755 "$TMP/idshim/id"
printf '\x00/usr/bin/pmset\x00/usr/sbin/system_profiler\x00' > "$TMP/sys/Contents/MacOS/Zest"
printf '\x00/usr/bin/pmset\x00/Users/usr/zest/\x00' > "$TMP/sysleak/Contents/MacOS/Zest"
case_ "system-folder login passes on system paths" 0 "$TMP/sys" "$TMP/idshim"
case_ "system-folder login still catches /Users/" 1 "$TMP/sysleak" "$TMP/idshim"

echo "test-bundle-paths: $checks checks, $fails failed"
[ "$fails" = 0 ]
