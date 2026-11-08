# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [2.1.0] - 2026-11-08

### Changed

- **The health check asks the game, not its process.** It looked for `srcds_linux64` in `/proc`, which a hung or stopped game keeps, and which Black Mesa's server kept on Docker Engine 29.4.2 with no socket at all while it reported healthy. `tools/healthcheck.sh`, mounted read-only, now sends A2S_INFO to the game port at the address it answers on (the one it is bound to, or the container's own when it binds 0.0.0.0, as Left 4 Dead 2 does) and is healthy only on the engine's reply; it handles the challenge Source servers may answer with first, tries twice for a map change, and ends within 7 seconds. It asks from inside the container, so it does not prove the port is published on the host or open in a firewall; the README says so. CI runs it in the pinned image against a stand-in (answers, challenge, silent, no socket), and on the real server changes the map and needs it answering again, then stops the game process with SIGSTOP and needs it red while the old check stays green.
- **The Docker Engine 29.4.2 note links GitHub's runner-image issue and its fix.** [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790) is the ubuntu-26.04 image shipping that release; [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205) moves it to 29.7.2. Documentation only.
## [2.0.4] - 2026-11-08

### Security

- **The Steam token and the RCON password are no longer on the server's command line.** They were passed to srcds as `+sv_setsteamaccount <token>` and `+rcon_password <password>`, so both sat in its arguments for as long as the server ran, where every user on the host reads them with `ps` (`/proc/<pid>/cmdline` is world-readable, and the host sees every container's processes). The compose file now hands them to the container as environment variables; `scripts/start-server.sh` writes them with the shell's own `printf` into `tf/cfg/secrets.cfg` (mode 600, the server's user), and the command line carries `+exec secrets.cfg` in their place, before `+map`, where the token was. A value holding a double quote or a line break, which a Source config line cannot carry, stops the start with a message instead of being cut. CI boots the real game with two random secrets, reads every command line on the runner and in the container, and requires neither to appear; RCON still answers with the password and refuses a wrong one.

### Fixed

- **CI boots the game again on GitHub's ubuntu-26.04 runner.** Since 2026-11-07 `ubuntu-latest` is that image, which ships Docker Engine 29.4.2, and that release alone answers the 32-bit `socketcall` system call with ENOSYS in its default seccomp profile ([moby/moby#52506](https://github.com/moby/moby/issues/52506)). SteamCMD could not get online: "!!! Fatal Error: Steamcmd needs to be online to update.", with Steam and the network both up. On 29.4.2, and only there, CI now gives the daemon the profile Docker 29.4.3 ships (moby/profiles seccomp v0.2.3, pinned by commit and checksum) before it starts the server; anywhere else the step does nothing. Measured on every affected template's pinned image in tf2-server-docker-compose run 42496129688.

### Changed

- **The README names Docker Engine 29.4.2.** That release alone stops SteamCMD, which this image runs to install and update the game: upgrade to 29.4.3 or later, which reverted the rule, or point the daemon's `seccomp-profile` at the profile 29.4.3 ships. Ubuntu 26.04's own `docker.io` (27.5.1) never had it.

### Added

- **`scripts/update-game.sh` names Docker Engine 29.4.2 when SteamCMD cannot get online.** It used to say only "could not ask Steam for the current build"; when SteamCMD's log carries either text that release produces, it now says the host's Docker may be 29.4.2 and what to do. `tests/steamcmd-offline.sh` feeds it both texts and a SteamCMD that answers nothing, which must not blame Docker.
## [2.0.3] - 2026-11-07

### Security

- **`gameservermanagers/gameserver:tf2` was rebuilt upstream**; the pin moved from `sha256:9971fa70c340…` to `sha256:114becc45621…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [2.0.2] - 2026-11-06

### Security

- **`gameservermanagers/gameserver:tf2` was rebuilt upstream**; the pin moved from `sha256:9459fc482a70…` to `sha256:9971fa70c340…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [2.0.1] - 2026-11-01

### Changed

- **The fall-back night is shown on a neutral zone.** `tests/timers.sh` reads Berlin's fall-back on 25 October 2026; any zone with a fall-back shows the same skip, and the test still fails on a calendar without `UTC`. The README and the timer's comment no longer name the night by date and hour.

### Added

- **Docker making the game directory root's is measured, and refused.** `tests/unwritable-game-dir.sh` creates a container, never started, with `working_dir: /data/tf2` on a fresh volume, the way the first 2.0 candidate's server was created, and finds `/data/tf2` owned by `0:0`; `scripts/update-game.sh`, as uid 1000, then exits 1 with "belongs to 0:0 ... SteamCMD cannot install there" before SteamCMD is called. A plant without the check hands SteamCMD the root-owned directory, and a control on a plain fresh volume gets a directory owned by uid 1000. `docs/evidence/steamcmd-unwritable-dir.md` keeps the CI log of the real SteamCMD in that situation: `Failed to create "/data/tf2/steamapps" folder.`, the game in its own library, and "Success! App '232250' fully installed.", exit 0.
## [2.0.0] - 2026-11-01

### Changed

- **The first start of 2.0 downloads the game, about 15 GB, into a new volume, `tf2-server-game`.** This is the one disruption, and why this is a major. Up to 1.x the game was baked into `lacledeslan/gamesvr-tf2`, and "a Valve update arrives as a new digest" assumed that image followed Valve. It was last built on 2026-08-13 and reports version 10828683 (its `steam.inf`, read in CI on 2026-11-01). Asked about that version, Steam's `UpToDateCheck` answers `up_to_date: false, version_is_listable: false, required_version: 11191711`: a server deployed from 1.x was healthy and answered every query, Steam's list did not show it, the current client could not join it, and CI was green, because it never asked Steam. The same `.env`, `server.cfg`, `mapcycle.txt`, `navs/` and port carry over. After moving, `docker image rm lacledeslan/gamesvr-tf2` gives back 11 GB. The README's "Moving from 1.x" has the three commands.
- **The game is brought to Steam's build every time the server starts.** `scripts/update-game.sh`, run by the server's own start script before srcds, compares the installed build id with Steam's and, when they differ, moves the old app manifest aside and validates against the current one. SteamCMD's own "already up to date" is not believed: on the machine this template comes from it said so twice about an old install, because Steam refuses an anonymous login the manifest of a build that is no longer current. It carries on whenever there is a game to start, so a Steam outage leaves the server on the build it has rather than down, and a restart is an update. It never runs under a running server, which a one-shot service, re-run by every `docker compose up -d`, could not promise. And it refuses a game directory it cannot write: Docker creates a container's working directory, and the parents of a bind mount's target, inside a volume as root, and SteamCMD given a directory it cannot write installs 15 GB into its own library and still prints "Success!". That is how the first candidate failed in CI; so nothing is mounted inside the game directory any more, and `server.cfg`, `mapcycle.txt` and `navs/` are linked in from `/config` after each update.
- **The runtime is LinuxGSM's `tf2` image, `gameservermanagers/gameserver:tf2`, rebuilt every week.** It carries the libraries, SteamCMD and python3; LinuxGSM itself does not run, because its update path believes SteamCMD's answer. The server runs as uid 1000 with every capability dropped, and its health check now allows 60 minutes for a first start (`TF2_SERVER_START_PERIOD`), since a first start is a download, not a map load.
- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

### Added

- **`tools/steam-uptodate.sh` and a systemd timer: Steam is asked every fifteen minutes whether the server is current.** It reads the version the server reports over A2S and asks `UpToDateCheck`. Behind with people on, it says so once and waits. Behind and empty, it restarts the server, which updates the game on the way up, and asks Steam again until Steam calls the new version current: the proof is Steam's answer, never the update's exit code. At most three updates in 24 hours, then it says so once and fails every run. One update per host per pass, by a lock and a stamp shared with the CS2, CS2 Classic and Left 4 Dead 2 templates: on the machine this template comes from, two 73 GB verifications back to back took a CPU to 81 °C. A silent server or Steam decides nothing, for up to six hours. Something new also goes to `STEAM_UPTODATE_NOTIFY` when it is set. The timer is on UTC with an `OnUnitActiveSec` net (`tests/timers.sh`), and the script is one brace group read whole before it runs (`tests/read-whole.sh`).
- **CI installs the game from Steam, boots it and asks Steam whether it is current.** Then it writes the August version into `steam.inf` and an older build into the app manifest, needs the check to call that out of date, and has `tools/steam-uptodate.sh` bring the server back with SteamCMD until Steam agrees. `tests/steam-uptodate.sh` drives every branch of the script against stubbed answers, with four plants, one rule taken out each.

### Fixed

- **rcon works.** The README said `docker compose -p tf2 exec tf2-server rcon status`; the 1.x image had no rcon program, so that command could only fail. `tools/rcon.sh` speaks the protocol from inside the server's container, with the password from `.env` on stdin, never in argv. CI checks `status` against the real server and a wrong password refused.
- **`update.sh` no longer stops without a word when a release adds a variable and no compose file requires one.** The search for `${VAR:?}` came back empty, and under `pipefail` that empty result ended the script with status 1 right after it listed the new variables.
- **`update.sh` stops on a `.env` it cannot read, before the checkout.** It used to fall through: every new required variable read as "not set", or, with none, the tree moved to the new tag and `docker compose up` failed on the permission. Now it names the file, its owner and mode, and changes nothing.
## [1.2.0] - 2026-09-22

### Added

- **`TF2_SERVER_TIMEZONE`: the game gets the household clock too.** Every timestamp this server writes — a ban, a join, the crash it leaves behind — is read next to a log line from somewhere else, and two clocks turn that into arithmetic. Six of this fleet's eleven game templates already carried the setting and this one did not. It defaults to UTC, which is now a choice rather than an accident, and the image carries the whole tz database so any zone name works. Measured against the pinned image: unset gives `UTC`, set gives the zone asked for.

## [1.1.0] - 2026-09-07

### Added

- **`update.sh`: move between release tags on purpose.** It updates to the latest release (a combination this repository's CI has booted and smoke-tested), refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved. `--dry-run` says what would happen.

s check is what notices a rebuild.
- **A health check anchored to the game binary rather than a substring.** Two
  commands run in the container: `srcds_linux64`, the game, and
  `srcds_run_64`, its restart wrapper. A substring search is satisfied by
  either, so the game can crash and leave the wrapper standing while the
  container reports healthy — and docker does not restart an unhealthy
  container by itself. `tests/e2e-healthcheck.sh` proves the distinction
  against a real container, with no game download.
- **The hostname in server.cfg, not on the command line.** The launcher drops
  everything after a `|` in an argument; a name passed through `.env` arrived
  truncated with no error.
- **A 24-slot casual rotation that bots keep alive.** `tf_bot_quota_mode fill`
  with a quota of six: bots yield slots as humans join, so the server never
  reads as empty in the browser. Every map on the rotation ran with a
  navigation mesh on the machine this template comes from; a `navs/` mount is
  there for maps that ship without one.
- **The published port equal to the port the server binds.** Steam's list
  records what the server bound, not what was forwarded, so a mismatch hands
  players an address where a different server answers.
- **Measured limits.** A full server peaked at 1.57 GB; the 4 GB ceiling
  exists so a leak here cannot get some other container OOM-killed in its
  place.
- **Deployment Verification CI**: shell and workflow linting, a Trivy scan of
  the pinned image, a daily freshness check on the pin, and the health-check
  suite. It deliberately does not boot the game: the image is 10 GB compressed,
  and a test that pretends a runner can hold it never runs.

[Unreleased]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.0.4...v2.1.0
[2.0.4]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.0.3...v2.0.4
[2.0.3]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/releases/tag/v1.0.0
