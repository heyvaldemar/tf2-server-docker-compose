#!/bin/sh
# update-game.sh - bring the Team Fortress 2 install in the game volume to the
# build Steam ships, before the server starts. scripts/start-server.sh runs it
# on every start of the container; tools/steam-uptodate.sh restarts an empty
# server that is behind, which runs this.
#
# WHY THE GAME LIVES IN A VOLUME. Up to v1 the game was baked into the image,
# and "updates arrive as a new image" assumed the image followed Valve. The
# image this template pinned was last built on 2026-08-13; Valve shipped TF2
# updates after it, and Steam stopped calling the version it carried current.
# A server deployed from it was healthy, answered every query, and could not
# be joined from the current client. So the game now lives in a volume and is
# updated here, by SteamCMD, from Steam itself.
#
# WHY STEAMCMD'S OWN ANSWER IS NOT TRUSTED. On the machine this template comes
# from, asked to update an old install, SteamCMD said "Success! App '232250'
# already up to date" twice, and with `validate` it failed with state 0x6. Its
# content log said why: "Failed to get manifest request code, 'Access Denied'"
# for the INSTALLED manifests. Steam does not hand an anonymous login the codes
# for a build that is no longer current, and SteamCMD needs the old manifest to
# work out a delta. So this compares build ids itself, and when they differ it
# moves the old app manifest aside and validates: SteamCMD then treats the
# files on disk as a fresh install against the CURRENT manifest and fetches
# only what differs. Measured there: 14.5 GB verified in about a minute.
#
# NEVER UNDER A RUNNING SERVER: it runs in the server's own container, before
# the server starts.
#
# EXITS 0 WHENEVER THERE IS A GAME TO START. A Steam outage must not keep the
# server down on the build it already has. Only an install with no game in it
# at all (a first start with Steam unreachable) exits 1, and the container's
# restart policy tries again. The outcome is the last line, "tf2-update: ...".
set -u
APP=232250
DIR=/data/tf2
ACF=$DIR/steamapps/appmanifest_$APP.acf
# SteamCMD's own home, kept in the volume: it bootstraps itself once (about
# 300 MB) instead of on every start, and keeps the manifests of the build it
# installed, which is what a delta needs.
export HOME=/data/steamcmd
mkdir -p "$DIR" "$HOME" 2>/dev/null
# A DIRECTORY STEAMCMD CANNOT WRITE IS NOT REPORTED BY STEAMCMD. Given one, it
# installs into its own library under $HOME instead and prints "Success!", so
# the game lands where the server never looks. That happened to the first 2.0
# candidate (the compose file says how), and it is refused here instead.
for d in /data "$DIR" "$HOME"; do
    if [ ! -w "$d" ]; then
        echo "tf2-update: $d belongs to $(stat -c %u:%g "$d" 2>/dev/null || echo nobody), and this runs as $(id -u):$(id -g); SteamCMD cannot install there"
        exit 1
    fi
done

buildid() {   # the installed build, from the app manifest
    sed -n 's/.*"buildid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$ACF" 2>/dev/null | head -1
}
installed() { [ -x "$DIR/srcds_run_64" ]; }
# The server looks for Steam's client library in its home, ~/.steam/sdk64; its
# home is the game directory (see the compose file). SteamCMD carries the
# library, so it is copied from there whenever it is missing or older.
client_lib() {
    lib=$(find "$HOME" -path '*linux64/steamclient.so' 2>/dev/null | head -1)
    if [ -z "$lib" ] || ! installed; then return 0; fi
    cmp -s "$lib" "$DIR/.steam/sdk64/steamclient.so" && return 0
    mkdir -p "$DIR/.steam/sdk64" && cp -f "$lib" "$DIR/.steam/sdk64/steamclient.so"
}
done_with() {   # message: the last line, and the exit status the server needs
    client_lib
    echo "tf2-update: $1"
    if installed; then exit 0; fi
    echo "tf2-update: there is no game in $DIR to start"
    exit 1
}

have=$(buildid)
# Steam's current public build. A SteamCMD that has just bootstrapped or
# updated itself sometimes answers the first request with no app info at all,
# so it is asked up to three times; what it said last is kept for the reader.
LOG=$HOME/app-info.log
want=""
for try in 1 2 3; do
    steamcmd +login anonymous +app_info_update 1 +app_info_print $APP +quit >"$LOG" 2>&1
    want=$(tr -d '\r' <"$LOG" | awk '/"branches"/ {b = 1} b && /"public"/ {p = 1}
                                   p && /"buildid"/ {gsub(/"/, "", $2); print $2; exit}')
    [ -n "$want" ] && break
    echo "tf2-update: SteamCMD gave no build on try $try"
done

if [ -z "$want" ]; then
    tr -d '\r' <"$LOG" | grep -v '^[[:space:]]*$' | tail -5 | sed 's/^/tf2-update:   steamcmd: /'
    done_with "could not ask Steam for the current build; starting on build ${have:-none}"
fi
if [ "$have" = "$want" ] && installed; then
    done_with "build $have is current"
fi

if [ -z "$have" ]; then
    echo "tf2-update: no game in the volume yet; downloading build $want (about 15 GB)"
else
    echo "tf2-update: installed build $have, Steam has $want; validating against it"
fi
[ -f "$ACF" ] && mv "$ACF" "$ACF.prev"
ULOG=$HOME/app-update.log
{ steamcmd +force_install_dir "$DIR" +login anonymous +app_update $APP validate +quit 2>&1
  echo "steamcmd exit status: $?"; } \
    | tr -d '\r' | tee "$ULOG" | grep -aE "Update state|Success!|Error!|ERROR|exit status"

now=$(buildid)
if [ "$now" = "$want" ]; then
    rm -f "$ACF.prev"
    done_with "updated build ${have:-none} -> $now"
fi
# Put the old manifest back if SteamCMD left none, so the next attempt starts
# from the same known state rather than from nothing.
[ -f "$ACF" ] || { [ -f "$ACF.prev" ] && mv "$ACF.prev" "$ACF"; }
grep -av '^[[:space:]]*$' "$ULOG" | grep -v 'Update state' | tail -4 | sed 's/^/tf2-update:   steamcmd: /'
find /data -maxdepth 6 -name "appmanifest_$APP.acf" 2>/dev/null | head -3 | sed 's/^/tf2-update:   app manifest found at: /'
# A SteamCMD the kernel killed for memory says nothing at all; the cgroup does.
if [ -r /sys/fs/cgroup/memory.events ]; then
    echo "tf2-update:   memory: peak $(( $(cat /sys/fs/cgroup/memory.peak 2>/dev/null || echo 0) / 1048576 )) MiB of $(cat /sys/fs/cgroup/memory.max), $(grep '^oom_kill ' /sys/fs/cgroup/memory.events)"
fi
done_with "FAILED to reach build $want (installed: $(buildid)); starting on what is there"
