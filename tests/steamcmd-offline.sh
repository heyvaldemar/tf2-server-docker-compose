#!/bin/bash
# scripts/update-game.sh names Docker Engine 29.4.2 when SteamCMD's "offline"
# is that release's seccomp profile, and says nothing of the kind otherwise.
#
# Docker Engine 29.4.2, and that release alone, answers the 32-bit
# socketcall(2) system call with ENOSYS (moby/moby#52506). SteamCMD is 32-bit
# and makes its sockets with it, so on such a host it prints, word for word
# from this repository's CI on the ubuntu-26.04 runner image:
#   [----] !!! Fatal Error: Steamcmd needs to be online to update.
# or, once bootstrapped:
#   CreateBoundSocket: failed to create socket, error [no name available] (38)
# with Steam and the network both up.
#
#   cases    each of the two texts: the explanation is printed, exit 1 (no
#            game to start); a SteamCMD that answers nothing at all: no
#            explanation, the same exit
#
# No download: steamcmd is a stub on PATH, in the pinned image, as uid 1000.
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
IMAGE=$(grep -m1 -oE '\$\{TF2_SERVER_IMAGE_TAG:-.*' tf2-server-docker-compose.yml | sed -E -e ':a' -e 's/\$\{[A-Z0-9_]+:-([^{}]*)\}/\1/' -e 'ta')
T=$(mktemp -d)
V="steamcmd-offline-$$"
cleanup() { docker volume rm -f "$V" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
chmod 644 scripts/update-game.sh

run_with() {  # what the stub prints: run the update against it on a fresh volume
  printf '#!/bin/sh\ncat <<"OUT"\n%s\nOUT\n' "$1" >"$T/steamcmd"
  chmod 755 "$T/steamcmd"
  docker volume rm -f "$V" >/dev/null 2>&1
  out=$(docker run --rm -u 1000:1000 --security-opt no-new-privileges:true --cap-drop ALL \
    -v "$V:/data" -v "$PWD/scripts/update-game.sh:/update-game.sh:ro" -v "$T/steamcmd:/usr/local/bin/steamcmd:ro" \
    --entrypoint /bin/sh "$IMAGE" /update-game.sh 2>&1); rc=$?
}
EXPLAINED="If this host runs Docker Engine 29.4.2"

echo "=== SteamCMD cannot download its own update ==="
run_with '[  0%] Checking for available update...
[----] !!! Fatal Error: Steamcmd needs to be online to update. Please confirm your network connection and try again.'
[ "$rc" = 1 ] && [[ $out == *"$EXPLAINED"*"29.4.3 or later"* ]] && pass "named: Docker Engine 29.4.2, and the upgrade" || fail "exit $rc, $out"

echo "=== SteamCMD cannot make a socket ==="
run_with 'Loading Steam API...CreateBoundSocket: failed to create socket, error [no name available] (38)
OK
Connecting anonymously to Steam Public...Retrying...'
[ "$rc" = 1 ] && [[ $out == *"$EXPLAINED"* ]] && pass "named: Docker Engine 29.4.2, and the upgrade" || fail "exit $rc, $out"

echo "=== control: SteamCMD answers nothing ==="
run_with ''
[ "$rc" = 1 ] && [[ $out != *"$EXPLAINED"* ]] && [[ $out == *"could not ask Steam for the current build"* ]] \
  && pass "no game and no answer: said so, and Docker is not blamed" || fail "exit $rc, $out"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
