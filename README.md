# TF2 server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/tf2-server-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Team Fortress 2 dedicated server, pinned by digest, with the details that only show up after running one: a 24-slot casual rotation that bots keep alive between humans.

```bash
git clone https://github.com/heyvaldemar/tf2-server-docker-compose
cd tf2-server-docker-compose
cp .env.example .env && $EDITOR .env          # a Steam token and an rcon password
docker compose -f tf2-server-docker-compose.yml -p tf2 up -d
```

The game is baked into the image, so the first start is a 10 GB pull and then a map load. Watch it:

```bash
docker compose -p tf2 logs -f tf2-server
docker compose -p tf2 ps          # healthy once srcds is up
```

## What this file knows that a fresh one does not

**The health check is anchored, because the wrapper is also called srcds.** Two commands run in this container: `srcds_linux64`, the game, and `srcds_run_64`, the script that restarts it. A check for the substring `srcds` is satisfied by either, so the game can crash and leave the wrapper standing while the container reports healthy — and docker does not restart an unhealthy container on its own, so nothing else catches it either. `tests/e2e-healthcheck.sh` proves the distinction against a real container: with the game killed, the anchored form goes red and the substring form stays green.

**The hostname is in server.cfg, not on the command line.** The launcher drops everything after a `|` in an argument. A name like `Casual | 24/7` passed through `.env` arrived as `Casual`, and nothing said so.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers: the connection succeeds, the handshake fails against the wrong game, and every log line blames the client.

**Bots need navigation meshes.** A bot on a map without one spawns and stands there. Valve's own maps ship meshes; for anything else, generate one on a local client with `nav_generate` and put the `.nav` file in `navs/`. The rotation shipped here was run with a mesh for every map on it.

**The log is flushed per line.** `sv_logflush 1` in server.cfg. Without it the engine buffers and flushes only on close, so a quiet server writes a log that reports zero bytes while people are talking. A busy server fills the buffer on its own, which is why the problem hides on the server you test and appears on the next one.

**The memory ceiling is measured, not guessed.** A full 24-slot server peaked at 1.57 GB; the 4 GB limit exists so a leak here cannot get some other container killed instead. With no limit at all the kernel's OOM killer chooses its victim by size, which means the process it kills is rarely the one at fault.

**Without a Steam token the server runs and is invisible.** It never joins the public list, which from a player's side is indistinguishable from a server that is down.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: players reach the relay, your router forwards nothing, and nothing at home listens on the internet. That pattern, including the local door so players in your own house do not travel to another country and back, is [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose).

One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
# rcon, using the password from .env
docker compose -p tf2 exec tf2-server rcon status

# change the map
docker compose -p tf2 exec tf2-server rcon changelevel pl_upward
```

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the image this repository has tested. The tag is `latest` because upstream publishes no version numbers: the digest is the version. When Valve ships an update, Laclede's LAN rebuilds the image, the daily freshness check goes red, and the pin moves deliberately. A client on a newer build than the server cannot connect, so this is worth acting on the day it happens. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

## Testing

`tests/e2e-healthcheck.sh` runs five assertions against a real container and needs no game download: the anchored check is green with the game running, the substring check is green too, and after the game is killed the anchored one goes red while the substring one stays green with the wrapper still standing.

CI runs it on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

CI does not boot the game. The image is 10 GB compressed, which is more than a GitHub runner has to give, and a test that pretends otherwise is a test that never runs.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
