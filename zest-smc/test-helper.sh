#!/bin/bash
# test-helper.sh: checks the privileged helper and its sudoers grant without root.
#
#   bash zest-smc/test-helper.sh
#
# 1. Builds main.swift into a temp folder and runs it as the current user: the removed
#    commands (limit-get, limit-set, read, size) are refused as unknown, lowpowermode
#    accepts only "0" or "1" and refuses to act without root, probe answers with the
#    helper interface number, and that number equals ZestHelper.interface in the app.
# 2. Prints the grant install-helper.sh would install (--print-sudoers, checked by visudo)
#    and requires exactly the four argument vectors, with no bare helper path, and that a
#    user name able to change the file's meaning (a newline, a space) is refused.
# 3. Reads every line of Sources/ that names sudo. Each `sudo -n` call must be covered by
#    that grant, so the app can never send a command the grant refuses; any other use of
#    sudo (a Process argument list, a split string) fails the test until it is listed here.
# ZEST_SMC_DIR points the test at another copy of main.swift and install-helper.sh (used
# to prove the test fails on the previous files). Exit 0 when every check passes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="${ZEST_SMC_DIR:-$HERE}"
DEST="/usr/local/libexec/zest/zest-smc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
checks=0
pass() { checks=$((checks + 1)); echo "ok   $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL $1"; }

# expect <name> <want exit> <want output prefix> <args...>; expect_exact compares the
# whole output instead of its start.
EXACT=0
expect() {
  local name="$1" want_rc="$2" want_out="$3"; shift 3
  local out rc=0 match=0
  out="$("$TMP/zest-smc" "$@" 2>&1)" || rc=$?
  if [ "$EXACT" = 1 ]; then [ "$out" = "$want_out" ] && match=1
  else [ "${out#"$want_out"}" != "$out" ] && match=1; fi
  if [ "$rc" = "$want_rc" ] && [ "$match" = 1 ]; then pass "$name"
  else fail "$name (exit $rc, output: $out)"; fi
}
expect_exact() { EXACT=1; expect "$@"; EXACT=0; }

if [ "$(id -u)" = "0" ]; then echo "run as a normal user: as root lowpowermode would really toggle" >&2; exit 2; fi

swiftc -O "$SRC/main.swift" -o "$TMP/zest-smc"
APP_IF="$(sed -n 's/^ *static let interface = \([0-9][0-9]*\)$/\1/p' "$ROOT/Sources/Zest/ChargeLimit/ChargeLimiter.swift")"
if [ -n "$APP_IF" ]; then pass "app expects helper interface $APP_IF"; else fail "app expects a helper interface"; fi
expect_exact "probe answers with the app's interface" 0 "ok helper ${APP_IF:-missing}" probe
expect "limit-get is gone" 2 "error unknown-command" limit-get
expect "limit-set is gone" 2 "error unknown-command" limit-set 1
expect "read is gone" 2 "error unknown-command" read CHWA
expect "size is gone" 2 "error unknown-command" size
expect "lowpowermode refuses 2" 2 "error bad-arg" lowpowermode 2
expect "lowpowermode refuses no argument" 2 "error bad-arg" lowpowermode
expect "lowpowermode refuses extra arguments" 2 "error bad-arg" lowpowermode 1 extra
expect "lowpowermode needs root" 1 "error not-root" lowpowermode 1

GRANT="$TMP/grant"
if bash "$SRC/install-helper.sh" --print-sudoers testuser > "$GRANT" 2>&1; then
  pass "grant passes visudo"
else
  fail "grant passes visudo ($(head -1 "$GRANT"))"
fi
cat > "$TMP/want" <<WANT
testuser ALL=(root) NOPASSWD: $DEST probe
testuser ALL=(root) NOPASSWD: $DEST lowpowermode 0
testuser ALL=(root) NOPASSWD: $DEST lowpowermode 1
testuser ALL=(root) NOPASSWD: /usr/bin/powermetrics --samplers tasks -n 1 -i 400
WANT
if cmp -s "$TMP/want" "$GRANT"; then pass "grant is exactly the four argument vectors"
else fail "grant is exactly the four argument vectors"; fi
if grep -qx "testuser ALL=(root) NOPASSWD: $DEST" "$GRANT"; then fail "no bare helper path in the grant"
else pass "no bare helper path in the grant"; fi
for bad in "$(printf 'x\nx ALL=(ALL) NOPASSWD: ALL')" "two words" "-n"; do
  rc=0; bash "$SRC/install-helper.sh" --print-sudoers "$bad" > "$TMP/bad" 2>&1 || rc=$?
  if [ "$rc" = 2 ] && ! grep -q NOPASSWD "$TMP/bad"; then pass "grant refuses user name: $(printf '%s' "$bad" | head -1)"
  else fail "grant refuses user name: $(printf '%s' "$bad" | head -1) (exit $rc)"; fi
done

# Every line in Sources/ that names sudo is a comment, the process-name list that keeps
# sudo out of the per-app energy table, or a `sudo -n` call checked below. Anything else
# is a sudo use this test cannot see, so it fails.
other=0
while IFS= read -r line; do
  code="${line#*:*:}"
  trimmed="$(printf '%s' "$code" | sed 's/^[[:space:]]*//')"
  case "$trimmed" in
    //*) continue ;;
    *'"sudo", "zest-smc"'*) continue ;;
    *'"sudo -n '*) continue ;;
  esac
  other=$((other + 1))
  fail "unrecognized sudo use in ${line%%:*}: $trimmed"
done < <(grep -rnw sudo "$ROOT/Sources")
if [ "$other" = 0 ]; then pass "no sudo use outside the recognized forms"; fi

# Every sudo call the app makes, as written in Sources/ (the helper's path is interpolated
# from ZestHelper; the Low Power argument is a "0" or "1" variable).
calls="$(grep -rhoE '"sudo -n [^"]*' "$ROOT/Sources" | sed -e 's/^"//' -e 's/ 2>.*$//' -e 's/ *$//')"
n=0
while IFS= read -r call; do
  [ -n "$call" ] || continue
  n=$((n + 1))
  case "$call" in
    'sudo -n \(ZestHelper.quote(helper)) probe') argv=("$DEST probe") ;;
    'sudo -n \(ZestHelper.quote(helper)) lowpowermode \(target)') argv=("$DEST lowpowermode 0" "$DEST lowpowermode 1") ;;
    'sudo -n /usr/bin/powermetrics '*) argv=("${call#sudo -n }") ;;
    *) fail "unknown sudo call in Sources: $call"; continue ;;
  esac
  for a in "${argv[@]}"; do
    if grep -qxF "testuser ALL=(root) NOPASSWD: $a" "$GRANT"; then pass "grant covers: $a"
    else fail "grant covers: $a"; fi
  done
done <<< "$calls"
if [ "$n" -ge 3 ]; then pass "read $n sudo calls in Sources"; else fail "read $n sudo calls in Sources (expected at least 3)"; fi

echo "test-helper: $checks checks, $fails failed"
[ "$fails" = 0 ]
