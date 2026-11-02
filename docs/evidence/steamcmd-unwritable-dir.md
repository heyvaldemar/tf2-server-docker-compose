# SteamCMD given a directory it cannot write: 15 GB elsewhere, and "Success!"

What a first 2.0 candidate of this template did on a fresh volume, kept here
because the Actions log that shows it expires after 90 days.

- Run: <https://github.com/heyvaldemar/tf2-server-docker-compose/actions/runs/41364443304>,
  job "where (runscript)", id 125021510016, 2026-11-01, on a proof branch
  (`proof/steamcmd-dir`, commit 0d74f85, since deleted).
- What ran: that candidate's compose file, brought up with `docker compose up -d`:
  a one-shot service, `tf2-update`, running `scripts/update-game.sh` as uid
  1000, and the server, which depended on it and had `working_dir: /data/tf2`
  inside the same volume. In this job the SteamCMD commands went in through
  `+runscript`, so SteamCMD echoes each one. Six other full runs of the same
  candidate, with the commands on the command line, left the game in the same
  place.

## What SteamCMD said

The update log, as written (terminal colour codes removed):

```text
steamcmd.sh[76]: Starting  /data/steamcmd/.local/share/Steam/steamcmd/linux32/steamcmd
Redirecting stderr to '/data/steamcmd/.local/share/Steam/logs/stderr.txt'
Logging directory: '/data/steamcmd/.local/share/Steam/logs'
[  0%] Checking for available updates...
[----] Verifying installation...
UpdateUI: skip show logo
Steam Console Client (c) Valve Corporation - version 1792617903
-- type 'quit' to exit --
Loading Steam API...OK
force_install_dir /data/tf2

Connecting anonymously to Steam Public...OK
Waiting for client config...OK
Waiting for user info...OK
app_update 232250 validate
Success! App '232250' fully installed.
quit
Unloading Steam API...OK
steamcmd exit status: 0
```

Its content log, the lines about where it installs:

```text
[2026-11-01 23:57:49] Load failed: /data/steamcmd/.local/share/Steam/steamapps/libraryfolders.vdf.
[2026-11-01 23:57:49] Load failed: /data/steamcmd/.local/share/Steam/config/libraryfolders.vdf.
[2026-11-01 23:57:49] Steam library folders configuration will be reset.
[2026-11-01 23:57:49] No install folder configuration files found.
[2026-11-01 23:57:49] Loaded 0 apps from install folder "/data/steamcmd/.local/share/Steam/steamapps\appmanifest_*.acf".
[2026-11-01 23:57:49] Triggered async write of Steam library folders configuration (1 libraries).
[2026-11-01 23:58:01] Failed to create "/data/tf2/steamapps" folder.
[2026-11-01 23:58:01] Loaded Steam library folders configuration: /data/steamcmd/.local/share/Steam/steamapps/libraryfolders.vdf
[2026-11-01 23:58:01] Loaded 0 apps from install folder "/data/steamcmd/.local/share/Steam/steamapps\appmanifest_*.acf".
[2026-11-01 23:58:05] AppID 232250 update started : download 0/10663397328, store 0/0, reuse 0/0, delta 0/0, stage 0/15245763276
[2026-11-01 23:58:05] Downloading 15724 chunks for depot 232250 (5757605357257765879)
```

## Where the files landed

Not in `/data/tf2`, the directory it was given, but in SteamCMD's own library
under its home:

```text
/data/steamcmd/.local/share/Steam/steamapps/appmanifest_232250.acf
/data/steamcmd/.local/share/Steam/steamapps/common/Team Fortress 2 Dedicated Server/srcds_run_64
```

This job printed only the script's first lines. In the repository's own CI
run of the same candidate,
<https://github.com/heyvaldemar/tf2-server-docker-compose/actions/runs/41360098901>,
the script read the build from `/data/tf2`, found none, and said so:

```text
tf2-update: no game in the volume yet; downloading build 26334371 (about 15 GB)
tf2-update:   found: /data/steamcmd/.local/share/Steam/steamapps/appmanifest_232250.acf
tf2-update: FAILED to reach build 26334371 (installed: ); starting on what is there
tf2-update: there is no game in /data/tf2 to start
```

The same run's job "where (up-d-oneshot)", id 125021510130, started the
one-shot alone, so the server container was never created. There SteamCMD
logged `Loaded 0 apps from install folder "/data/tf2/steamapps\appmanifest_*.acf"`
and the game landed in `/data/tf2`.

## Why

Docker creates a container's missing working directory when it creates the
container, owned by root, and `docker compose up -d` creates the server's
container before it starts the one-shot. With `working_dir: /data/tf2`
inside the volume, `/data/tf2` belonged to root before SteamCMD ran, and
SteamCMD, as uid 1000, could not create `steamapps` in it. It did not stop: it
installed into its own library and reported success.

`tests/unwritable-game-dir.sh` measures that on every push: a container
created, never started, with that working directory leaves `/data/tf2` owned
by `0:0`, and `scripts/update-game.sh` then refuses it, exit 1, with
"belongs to 0:0 ... SteamCMD cannot install there", before SteamCMD is called.
Since 2.0.0 the server has no working directory and nothing mounted inside the
game directory.
