# TF2 server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/workflows/deployment-verification.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14886/badge)](https://www.bestpractices.dev/projects/14886)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Team Fortress 2 dedicated server that Steam calls up to date, with the details that only show up after running one: a 24-slot casual rotation that bots keep alive between humans.

```bash
git clone https://github.com/heyvaldemar/tf2-server-docker-compose
cd tf2-server-docker-compose
cp .env.example .env && $EDITOR .env          # a Steam token and an rcon password
docker compose -f tf2-server-docker-compose.yml -p tf2 up -d
```

**The first start downloads the game into a volume, about 15 GB.** After that every start compares the installed build with Steam's, which takes seconds. Watch it:

```bash
docker compose -p tf2 logs -f tf2-server      # the download, "tf2-update: ...", then srcds
docker compose -p tf2 ps                      # healthy once srcds is up
tools/steam-uptodate.sh --check               # what Steam says about it
```

## What this file knows that a fresh one does not

**Steam is asked whether the server is current, because nothing else knows.** Up to v1 the game was baked into the image, pinned by digest, and "a Valve update arrives as a new digest" assumed the image followed Valve. The pinned image was built on 2026-08-13 and reports version 10828683; Steam's `UpToDateCheck` has called that out of date since Valve's next update ("required 11191711" on 2026-11-01). Steam also answers `version_is_listable: false`: a server deployed from v1 was healthy and answered every query, Steam's list did not show it, the current client could not join it, and this repository's CI was green throughout, because it never asked. The game now lives in a volume and is brought to Steam's build every time the server starts, CI boots it and asks Steam about the version the server itself reports, and `tools/steam-uptodate.sh` asks the same question every fifteen minutes on the host.

**SteamCMD's "already up to date" is not believed.** On the machine this template comes from, asked to update an old install, SteamCMD answered "Success! App '232250' already up to date" twice, and with `validate` failed with state 0x6; its content log said "Failed to get manifest request code, 'Access Denied'" for the installed manifests. Steam does not give an anonymous login the codes for a build that is no longer current. So `scripts/update-game.sh` compares build ids itself, and when they differ moves the old app manifest aside and validates against the current one, which fetches only the files that changed. CI does exactly that to a server made stale on purpose.

**The game is never updated under a running server.** The update runs in the server's own container, before srcds starts, so a restart is the update and nothing changes the files while srcds has them open. A separate one-shot service would be re-run by every `docker compose up -d`, server up or not.

**Nothing is mounted inside the game directory, and Docker is not given a working directory there.** Docker creates both, inside the volume, as root. The first 2.0 candidate had `working_dir: /data/tf2`, so on a fresh volume the game directory belonged to root before SteamCMD ran; SteamCMD, as uid 1000, installed all 15 GB into its own library instead and printed "Success! App '232250' fully installed." anyway. `scripts/update-game.sh` refuses a directory it cannot write, and `server.cfg`, `mapcycle.txt` and `navs/` are mounted under `/config` and linked into place after every update.

**The health check is anchored, because the wrapper is also called srcds.** Two commands run in this container: `srcds_linux64`, the game, and `srcds_run_64`, the script that restarts it. A check for the substring `srcds` is satisfied by either, so the game can crash and leave the wrapper standing while the container reports healthy — and docker does not restart an unhealthy container on its own, so nothing else catches it either. `tests/e2e-healthcheck.sh` proves the distinction against a real container: with the game killed, the anchored form goes red and the substring form stays green.

**The hostname is in server.cfg, not on the command line.** The launcher drops everything after a `|` in an argument. A name like `Casual | 24/7` passed through `.env` arrived as `Casual`, and nothing said so.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers: the connection succeeds, the handshake fails against the wrong game, and every log line blames the client.

**Bots need navigation meshes.** A bot on a map without one spawns and stands there. Valve's own maps ship meshes; for anything else, generate one on a local client with `nav_generate` and put the `.nav` file in `navs/`. The rotation shipped here was run with a mesh for every map on it.

**The log is flushed per line.** `sv_logflush 1` in server.cfg. Without it the engine buffers and flushes only on close, so a quiet server writes a log that reports zero bytes while people are talking. A busy server fills the buffer on its own, which is why the problem hides on the server you test and appears on the next one.

**The memory ceiling is measured, not guessed.** A full 24-slot server peaked at 1.57 GB; the 4 GB limit exists so a leak here cannot get some other container killed instead. With no limit at all the kernel's OOM killer chooses its victim by size, which means the process it kills is rarely the one at fault.

**Without a Steam token the server runs and is invisible.** It never joins the public list, which from a player's side is indistinguishable from a server that is down.

**Docker Engine 29.4.2 stops SteamCMD, and only that release does.** Its default seccomp profile answers the 32-bit `socketcall` system call with "not implemented" ([moby/moby#52506](https://github.com/moby/moby/issues/52506); for GitHub Actions, the ubuntu-26.04 runner image ships it: [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), with the move to 29.7.2 in [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205)), and SteamCMD is a 32-bit program that makes every socket with it. With Steam and the network both up, it prints `!!! Fatal Error: Steamcmd needs to be online to update.` or `CreateBoundSocket: failed to create socket, error [no name available] (38)`, and the game is never installed or updated: `scripts/update-game.sh` says which. Measured in [a CI run on GitHub's ubuntu-26.04 runner, which ships 29.4.2](docs/evidence/docker-29.4.2-socketcall.md): SteamCMD failed in this template's pinned image there, and logged in once the daemon had the profile Docker 29.4.3 ships. 29.4.3 reverted the rule, and Ubuntu 26.04's own `docker.io` (27.5.1) never had it. Check with `docker version --format '{{.Server.Version}}'` and upgrade; until you can, point [`seccomp-profile` in `daemon.json`](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) at [moby/profiles seccomp v0.2.3](https://github.com/moby/profiles/blob/836ae4d37ef2ec995c77c99fc55f5b5f3af3a897/seccomp/default.json) and restart Docker.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: players reach the relay, your router forwards nothing, and nothing at home listens on the internet. That pattern, including the local door so players in your own house do not travel to another country and back, is [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose).

One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
# rcon, using the password from .env
tools/rcon.sh status

# change the map
tools/rcon.sh changelevel pl_upward
```

Up to v1 this said `docker compose -p tf2 exec tf2-server rcon status`. The image had no rcon program, so that command could only fail. `tools/rcon.sh` speaks the rcon protocol from inside the server's own container, takes the password from `.env` on stdin rather than the command line where `ps` would show it, and CI checks `status` against the real server and a wrong password refused.

## Keeping the game current

**The game: `scripts/update-game.sh`, at every start of the server.** It asks Steam which build is current and compares it with the one in the volume; when they differ it validates the install against Steam's manifest, about a minute for 15 GB on a fast disk. It carries on whenever there is a game to start, so a Steam outage leaves the server on the build it has instead of down, and its last line says what happened: `docker compose -p tf2 logs tf2-server | grep tf2-update: | tail -1`.

**When a running server falls behind: `tools/steam-uptodate.sh`, on a timer, every fifteen minutes.** Valve ships updates at any hour, and a server on the old build turns away every player on the new client while its container stays healthy. The script reads the version the server reports over A2S and asks Steam's `UpToDateCheck` about it:

- **current**: nothing.
- **behind, people on**: it says so once and waits. An update drops them.
- **behind, nobody on**: it restarts the server, which updates the game on the way up, and asks Steam again until Steam calls the new version current. Steam's answer is the proof, not the restart.
- **still behind after three updates in 24 hours**: it says so once, stops trying, and fails every run, so the timer shows up in `systemctl --failed`.
- **no answer** from the server or from Steam: nothing is decided. A player count it cannot read is never zero. Six hours of silence (`STEAM_UPTODATE_SILENCE`) and it fails, because a check that can never tell is one somebody should look at.

**One update per host per pass.** On the machine this template comes from, two CS2 servers behind on the same evening were updated back to back, each restart had SteamCMD verify 73 GB, and the CPU reached 81 °C. The CS2, CS2 Classic and Left 4 Dead 2 templates ship the same script, and all of them take one host-wide lock around an update and leave a stamp beside it (`/var/tmp/steam-uptodate.*`), so a second server that is behind waits for a pass fifteen minutes after the first one finished. Their timers fire three minutes apart for the same reason.

"Says so" is one line in the journal every run, and, when `STEAM_UPTODATE_NOTIFY` is set, a message on its stdin the first time something new happens: a webhook, mail, anything that reads stdin. The service file has an example.

```bash
# edit the two paths in the service file to where this repository is checked out
sudo cp systemd/steam-uptodate.service systemd/steam-uptodate.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now steam-uptodate.timer
tools/steam-uptodate.sh --dry-run    # what it would do right now
```

**The timer runs on UTC, with a net under it.** The night the clocks went back an hour, the server this template comes from ran none of its local-time timers for that hour: systemd reads a local calendar such as `*:0/15` in wall-clock time and took the repeated hour as already gone. A calendar in UTC has no repeated hour, and `OnUnitActiveSec=16min` makes up a run missed for any other reason. `tests/timers.sh` checks both with `systemd-analyze` from one second before a fall-back (Berlin's, on 25 October 2026).

**Every script in `tools/` is read whole before it runs.** bash reads a script as it executes it, and after each command reads on from the same byte offset in whatever the file holds by then; on the server this template comes from, a timer started a script while its file was being edited in place, and the run died on a syntax error. Each script's body is one brace group, which bash parses in full before the first line runs, ending in `exit`.

## Updating

**The template:** the pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the image this repository has tested. Since v2 the image is the runtime only: LinuxGSM's weekly `tf2` image, for its libraries, SteamCMD and python3. LinuxGSM itself does not run, because its update path believes SteamCMD's answer. The tag carries no version; the digest is the version, and the daily freshness check goes red when it moves. `./update.sh` moves to the latest release tag on purpose, refuses to cross a major unattended, and names any new required variable before anything has moved.

### Moving from 1.x

**The first start of 2.0 downloads the game, about 15 GB, into the new `tf2-server-game` volume.** Nothing else changes for a running server: the same `.env`, the same `server.cfg`, `mapcycle.txt` and `navs/`, the same port. Plan the download, and the disk:

```bash
./update.sh --allow-major                    # moves to v2.0.0 and brings the stack up
docker compose -p tf2 logs -f tf2-server     # the download, then srcds
docker image rm lacledeslan/gamesvr-tf2      # the old image: 11 GB back
```

The volume holds nothing but the game, so `docker compose down -v` costs a download and nothing else; it is not declared external for that reason.

## Testing

CI installs the game from Steam and boots it on every push, the way a first start does, then:

- asks Steam about the version the server reports, with `tools/steam-uptodate.sh --check`, and fails unless Steam calls it current;
- sends `status` over rcon and needs the hostname line back, and a wrong password refused;
- **plants a stale server**: the August image's version, 10828683, written into `steam.inf` and an older build into the app manifest, and the check must call it out of date;
- runs `tools/steam-uptodate.sh` for real against that server, and needs it to update the game with SteamCMD and Steam to agree afterwards.

Without a game:

- `tests/steam-uptodate.sh` drives every branch of the script against stubbed A2S and Steam answers, then runs four copies with one rule taken out each (the player count, the proof by Steam, the host lock, the daily limit) and sees each do what the rule prevents.
- `tests/unwritable-game-dir.sh` creates a container, never started, with `working_dir: /data/tf2` on a fresh volume, as the first 2.0 candidate's server was, and finds `/data/tf2` owned by root; `scripts/update-game.sh` then refuses it before calling SteamCMD. A plant without the check hands SteamCMD that directory, which is what made the real one install 15 GB elsewhere and print "Success!" ([the log](docs/evidence/steamcmd-unwritable-dir.md)).
- `tests/steamcmd-offline.sh` feeds `scripts/update-game.sh` the two texts SteamCMD prints under Docker Engine 29.4.2, and needs the script to name that release; a SteamCMD that answers nothing at all must not be blamed on Docker.
- `tests/read-whole.sh` rewrites the script's own file in place under a running copy, with and without its braces.
- `tests/timers.sh` checks the timer against the night the clocks went back.
- `tests/e2e-healthcheck.sh` runs five assertions against a real container: the anchored check is green with the game running, the substring check is green too, and after the game is killed the anchored one goes red while the substring one stays green with the wrapper still standing.

All of it alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
