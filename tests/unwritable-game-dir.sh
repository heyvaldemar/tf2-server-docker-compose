#!/bin/bash
# scripts/update-game.sh refuses a game directory it cannot write, and Docker
# is what makes one.
#
# The first 2.0 candidate gave the server working_dir: /data/tf2, inside the
# game volume. Docker creates a missing working directory when it creates the
# container, owned by root, so on a fresh volume /data/tf2 belonged to root
# before the update ran. SteamCMD, running as uid 1000, could not write it,
# installed 15 GB into its own library instead and printed "Success! App
# '232250' fully installed." (docs/evidence/steamcmd-unwritable-dir.md).
#
#   measured  a fresh volume and a container CREATED on it with working_dir
#             /data/tf2, never started: /data/tf2 then exists, owned by 0:0
#   refused   scripts/update-game.sh in the pinned image, as uid 1000, on that
#             volume: exit 1, "belongs to 0:0 ... SteamCMD cannot install
#             there", and SteamCMD never called
#   plant     the same script with the check taken out: it hands SteamCMD the
#             directory it cannot write
#   control   a fresh volume with no working_dir: the script makes /data/tf2
#             itself, owned by 1000:1000, and goes on to SteamCMD
#
# No download: steamcmd is a stub on PATH that writes down how it was called
# and answers a current build of "1" and "Success!".
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
IMAGE=$(grep -m1 -oE '\$\{TF2_SERVER_IMAGE_TAG:-.*' tf2-server-docker-compose.yml | sed -E -e ':a' -e 's/\$\{[A-Z0-9_]+:-([^{}]*)\}/\1/' -e 'ta')
T=$(mktemp -d)
V="unwritable-game-dir-$$"
cleanup() { docker rm -f "$V-created" >/dev/null 2>&1; docker volume rm -f "$V-a" "$V-b" "$V-c" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
[ -n "$IMAGE" ] && pass "the pinned image: ${IMAGE%%@*}" || { fail "no image pin in the compose file"; exit 1; }

cat >"$T/steamcmd" <<'STUB'
#!/bin/sh
echo "$*" >>/data/steamcmd-calls
case "$*" in
  *app_info_print*) printf '"branches"\n{\n"public"\n{\n"buildid"\t\t"1"\n}\n}\n' ;;
  *) echo "Success! App '232250' fully installed." ;;
esac
STUB
chmod 755 "$T/steamcmd"
chmod 644 scripts/update-game.sh
update() {  # volume script: run the update as the server does, uid 1000
  docker run --rm -u 1000:1000 --security-opt no-new-privileges:true --cap-drop ALL \
    -v "$1:/data" -v "$2:/update-game.sh:ro" -v "$T/steamcmd:/usr/local/bin/steamcmd:ro" \
    --entrypoint /bin/sh "$IMAGE" /update-game.sh 2>&1
}
peek() {  # volume command: look inside it as root
  docker run --rm -u 0 -v "$1:/data" --entrypoint /bin/sh "$IMAGE" -c "$2" 2>/dev/null
}

echo "=== measured: working_dir inside the volume ==="
docker volume create "$V-a" >/dev/null
docker create --name "$V-created" -u 1000:1000 -w /data/tf2 -v "$V-a:/data" --entrypoint /bin/true "$IMAGE" >/dev/null
owner=$(peek "$V-a" 'stat -c %u:%g /data/tf2 2>/dev/null || echo absent')
[ "$owner" = 0:0 ] && pass "created, never started, with working_dir /data/tf2: the directory exists in the volume, owned by $owner" \
  || fail "after docker create, /data/tf2 is: $owner (expected 0:0)"

echo "=== refused ==="
out=$(update "$V-a" "$PWD/scripts/update-game.sh"); rc=$?
printf '    %s\n' "${out//$'\n'/$'\n'    }"
calls=$(peek "$V-a" 'cat /data/steamcmd-calls 2>/dev/null')
[ "$rc" = 1 ] && [[ $out == *"/data/tf2 belongs to 0:0"*"SteamCMD cannot install there"* ]] && [ -z "$calls" ] \
  && pass "exit 1, said whose directory it is, and SteamCMD was never called" || fail "exit $rc, SteamCMD calls: ${calls:-none}"

echo "=== plant: the check taken out ==="
awk '/^for d in \/data "\$DIR" "\$HOME"; do$/ {skip = 1} skip && /^done$/ {skip = 0; next} !skip' scripts/update-game.sh >"$T/no-check.sh"
chmod 644 "$T/no-check.sh"
grep -q 'cannot install there' "$T/no-check.sh" && fail "the plant still has the check"
docker volume create "$V-b" >/dev/null
docker rm -f "$V-created" >/dev/null 2>&1
docker create --name "$V-created" -u 1000:1000 -w /data/tf2 -v "$V-b:/data" --entrypoint /bin/true "$IMAGE" >/dev/null
update "$V-b" "$T/no-check.sh" >/dev/null
calls=$(peek "$V-b" 'cat /data/steamcmd-calls 2>/dev/null')
[[ $calls == *"force_install_dir /data/tf2"*"app_update 232250 validate"* ]] \
  && pass "without the check, SteamCMD is handed /data/tf2, owned by root: what the real one answered with 15 GB elsewhere and Success" \
  || fail "the plant did not reach SteamCMD: ${calls:-no calls}"

echo "=== control: no working_dir ==="
docker volume create "$V-c" >/dev/null
out=$(update "$V-c" "$PWD/scripts/update-game.sh"); rc=$?
owner=$(peek "$V-c" 'stat -c %u:%g /data/tf2')
calls=$(peek "$V-c" 'cat /data/steamcmd-calls 2>/dev/null')
[ "$owner" = 1000:1000 ] && [[ $calls == *"force_install_dir /data/tf2"* ]] && [[ $out != *"cannot install there"* ]] \
  && pass "a fresh volume: the script made /data/tf2 itself, owned by $owner, and went on to SteamCMD" || fail "control: owner $owner, exit $rc, $out"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
