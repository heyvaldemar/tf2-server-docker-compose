# Docker Engine 29.4.2 stops SteamCMD and 32-bit srcds

Why this template's CI went red on 2026-11-07, and which game templates a
host on that Docker release breaks. Kept here because the Actions log that
shows it expires after 90 days.

## The cause

Docker Engine 29.4.2 vendors moby/profiles seccomp v0.2.2, whose default
profile has this rule ([moby/profiles 7158007a83](https://github.com/moby/profiles/commit/7158007a83),
"Block socketcall to prevent AF_ALG filter bypass"):

```json
{ "names": ["socketcall"], "action": "SCMP_ACT_ERRNO", "errnoRet": 38 }
```

`socketcall(2)` is how 32-bit x86 programs built against older libraries make
every socket. Error 38 is ENOSYS, "not implemented". SteamCMD is 32-bit, and
so is Left 4 Dead 2's srcds. The rule was reverted six days later
([3c28324314](https://github.com/moby/profiles/commit/3c28324314)), and Docker
Engine 29.4.3 ships seccomp v0.2.3, which allows `socketcall` again; 29.5.0
and 29.9.3 do too. The upstream report is
[moby/moby#52506](https://github.com/moby/moby/issues/52506), "SteamCMD
Errors on 29.4.2".

GitHub's `ubuntu-latest` became the ubuntu-26.04 image for this repository on
2026-11-07, and that image ships Docker Engine 29.4.2; the ubuntu-24.04 image
ships 28.0.4. GitHub's tracking issue is
[actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790),
"Ubuntu 26.04: Docker 29.4.2 blocks socketcall, so i386 containers have no
network", open since 2026-09-26; the fix,
[actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205),
moves the image to Docker 29.7.2 and was not merged on 2026-11-08. Once it is,
the CI step below finds another version and does nothing. Both run kernel 7.0 (7.0.0-1019-azure and 7.0.0-1017-azure), so
the kernel is not the difference. Ubuntu 26.04's own `docker.io` package is
27.5.1 and never had the rule.

## Ruled out first

Run [42492195427](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/runs/42492195427),
`steamcmd/steamcmd:latest` on the 26.04 runner: the same failure on the
default bridge, with `--network host`, with `--dns 1.1.1.1`, on a bridge with
MTU 1400, and with IPv6 off in the container. Every one printed:

```text
Loading Steam API...CreateBoundSocket: failed to create socket, error [no name available] (38)
Connecting anonymously to Steam Public...Retrying...
```

The same image on the 24.04 runner logged in.

## Every affected template, before and after

Run [42496129688](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/runs/42496129688),
job "sweep" (128778766480), on the 26.04 runner with Docker 29.4.2. Each
template's pinned image ran its own SteamCMD with `+login anonymous +quit` as
uid 1000 with every capability dropped; Left 4 Dead 2 and Black Mesa ran from
their own compose files for 150 seconds. Then the daemon was given the
profile Docker 29.4.3 ships (moby/profiles seccomp v0.2.3, commit 836ae4d,
sha256 536529b6…), Docker was restarted, and the same ran again.

| template | default profile of 29.4.2 | with 29.4.3's profile |
| --- | --- | --- |
| tf2 (LinuxGSM tf2 image) | `!!! Fatal Error: Steamcmd needs to be online to update.` | logged in |
| cs2, cs2-classic (joedwards32/cs2) | the same | logged in |
| kf2 (LinuxGSM kf2 image) | the same | logged in |
| humanitz (LinuxGSM hz image) | the same | logged in |
| vein (mbround18/vein-docker) | the same | logged in |
| zomboid (danixu86/project-zomboid-dedicated-server) | the same | logged in |
| `steamcmd/steamcmd:latest` | the same | logged in |
| l4d2 (32-bit srcds, game in the image) | unhealthy, 17 restarts in 150 s | healthy, 0 restarts |
| blackmesa (32-bit srcds, game in the image) | healthy, 0 restarts, but see below | (not run: l4d2 held the port) |

**Black Mesa is affected too, silently.** This sweep only read its health and
its restarts, and a first reading of it as "not affected" was wrong. Run
[42503040679](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/runs/42503040679)
in the Black Mesa template measured the network, 90 seconds after the server
reported healthy, on the same 29.4.2 runner:

| Black Mesa | default profile of 29.4.2 | with 29.4.3's profile |
| --- | --- | --- |
| health | healthy, 0 restarts | healthy, 0 restarts |
| A2S query | no answer (timed out) | answered |
| `tools/rcon.sh status` | nothing accepted a connection | `hostname: Black Mesa Crossfire 24/7` |

Its 32-bit srcds stays up with no socket at all, and a health check that looks
for the process stays green over a server nobody can reach.

The Jedi Academy template was not measured. Its server binary (`linuxjampded`,
2009) is 32-bit too, but its CI deliberately starts it without the game's
assets, which it refuses, so a green run there says nothing about its network
on 29.4.2.

## What the templates do about it

- CI, in the templates whose CI runs SteamCMD or 32-bit srcds (tf2, l4d2,
  humanitz, blackmesa): on Docker 29.4.2, and only there, the daemon gets
  29.4.3's profile, pinned by commit and checksum, before the server starts.
- README, in every affected template: Docker Engine 29.4.2 named, with the
  upgrade and, until then, the daemon's `seccomp-profile` pointed at 29.4.3's
  profile.
- `scripts/update-game.sh` here says, when SteamCMD's log carries either text
  above, that the host's Docker may be 29.4.2 (`tests/steamcmd-offline.sh`).
