#!/bin/sh
# start-server.sh - bring the game in the volume to Steam's build, link this
# repository's files into it, then start it. Every start of the container
# runs all three, in this order, so the game is never updated under a running
# server and a restart is an update.
#
# THE FILES ARE LINKED, NOT MOUNTED IN PLACE. A bind mount whose target is
# inside the volume makes Docker create the missing directories on the way
# to it as root, before anything here runs, and SteamCMD (uid 1000) then
# cannot write the game directory: see the compose file. So server.cfg,
# mapcycle.txt and navs/ are mounted under /config and linked into the game
# after the update, every start, which also puts back a link an update
# replaced with a file of Valve's.
set -u
/bin/sh /update-game.sh || exit 1
cd /data/tf2 || exit 1
# THE TOKEN AND THE RCON PASSWORD GO IN A FILE, NOT ON THE COMMAND LINE. As
# +sv_setsteamaccount and +rcon_password they sat in srcds's arguments for as
# long as the server ran, and every user on the host reads a process's
# arguments with ps. The shell's own printf writes them into a file only this
# user reads, and the compose file runs it with +exec secrets.cfg. A Source
# config value cannot carry a double quote or a line break: refused, not cut.
cfg_value() {  # cfg_value <name> <value>: refuses what a config line cannot hold
    case $2 in
        '') echo "start-server: $1 is not set" >&2; return 1 ;;
        *'"'*|*'
'*) echo "start-server: $1 holds a double quote or a line break, which a Source config file cannot carry" >&2; return 1 ;;
    esac
}
cfg_value TF2_SERVER_STEAM_TOKEN "${TF2_SERVER_STEAM_TOKEN:-}" || exit 1
cfg_value TF2_SERVER_RCON_PASSWORD "${TF2_SERVER_RCON_PASSWORD:-}" || exit 1
( umask 077 && printf 'sv_setsteamaccount "%s"\nrcon_password "%s"\n' "$TF2_SERVER_STEAM_TOKEN" "$TF2_SERVER_RCON_PASSWORD" > tf/cfg/secrets.cfg ) || exit 1
ln -sfn /config/server.cfg tf/cfg/server.cfg
ln -sfn /config/mapcycle.txt tf/cfg/mapcycle.txt
mkdir -p tf/custom
if [ -d tf/custom/navs ] && [ ! -L tf/custom/navs ]; then
    echo "start-server: tf/custom/navs is a directory in the volume, not the link to navs/; left as it is" >&2
else
    ln -sfn /config/navs tf/custom/navs
fi
exec ./srcds_run_64 "$@"
