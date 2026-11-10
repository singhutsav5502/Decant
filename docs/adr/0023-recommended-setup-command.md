# 0023. Define the recommended setup once, in `decant setup`

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Utsav, Claude

## Context
By 0.8.0 the setup that works is settled: one bottle, `games`, on CrossOver Wine 26.1.0 built locally with
Decant's patches, `BACKEND=auto` (ADR-0019), DXMT and DXVK installed, and D3DMetal imported from the user's
GPTK, with `games` as the default bottle (ADR-0016). That was only written down in the Hades II
investigation notes, and a new user had to piece it together from five commands. The README quick start
still described an older setup (a `steam` bottle with `--backend dxmt`). With Decant going open source,
people starting from nothing need one way to get the setup that's known to work.

## Decision
- `decant setup [--build-wine] [--gptk <dir>]` builds the recommended setup in five steps: a prebuilt
  Wine; CrossOver `26.1.0` built with `scripts/build-wine.sh` (only with `--build-wine`, since it takes
  15-40 minutes and needs Xcode and Homebrew); the DXMT and DXVK backends; D3DMetal (only from `--gptk`,
  never downloaded); and the bottle `games`, created as the default.
- The recommended values live in one place in `bin/decant` (`SETUP_BOTTLE`, `SETUP_WINE_MODE`,
  `SETUP_WINE_VERSION`). The bottle's settings are `bottle_create`'s defaults, so `setup` and
  `bottle create` can't drift apart.
- Each step is skipped when it's already done, so `setup` is safe to re-run. It never changes an existing
  bottle's settings or replaces a default bottle the user picked; where an existing `games` bottle is on a
  runtime without Metal, it prints the `bottle set` command instead of moving it.
- The app's Components sheet has **Set Up Recommended**, which runs `decant setup` without
  `--build-wine` (the app bundle doesn't include `scripts/` or `patches/`).

## Alternatives considered
- **A `games` bottle template file (a `.conf` copied into new homes):** a second copy of the defaults
  `bottle_create` already writes, and it can't install runtimes or backends.
- **Create `games` automatically on first launch:** downloads hundreds of MB without asking, and would
  surprise users who already have bottles.
- **Always build CrossOver Wine in setup:** too slow and too many prerequisites for a default; DXVK on the
  prebuilt Wine works for most DX9-11 games in the meantime.

## Consequences
New users get the known-good setup with one command, and the docs point at it. Moving to a newer CrossOver
release means changing `SETUP_WINE_VERSION` and checking that `patches/crossover/` still applies.
`--build-wine` only works from a source checkout. Setup's own tests run with fake runtimes and backends
that are already present, so the download and build paths are only checked by hand.
