# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-07

### Added

- **A Team Fortress 2 dedicated server**, image pinned by digest as an
  interpolation default, so `git pull` delivers the build this repository has
  tested and `.env` overrides survive it. The tag is `latest` because upstream
  publishes no version numbers: the digest is the version, and the daily
  freshness check is what notices a rebuild.
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

[Unreleased]: https://github.com/heyvaldemar/tf2-server-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/tf2-server-docker-compose/releases/tag/v1.0.0
