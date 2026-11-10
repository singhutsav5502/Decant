# 0002. Use prebuilt Gcenx Wine by default; self-built Wine is optional

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** Utsav, Claude

## Context
Building Wine for macOS needs an x86_64 Homebrew under Rosetta, mingw, and 20-40 minutes. Gcenx publishes
current macOS builds of `wine-devel` and `wine-staging` (`Gcenx/macOS_Wine_builds`). They include
MoltenVK, and the new WoW64 mode that macOS needs, since it has no 32-bit processes. CrossOver's patched
source adds msync and other Mac patches, but it's fiddly to build.

## Decision
`decant runtime install [staging|devel]` downloads the newest Gcenx tarball and normalises it to
`runtimes/<flavor>-<version>/{bin,lib,share}`. `scripts/build-wine.sh upstream|crossover <version>` builds
from source and registers the result with `decant runtime import`. Runtimes are immutable once
installed (see ADR-0003).

## Alternatives considered
- **Always build from source:** too slow and fragile as the default first-run experience.
- **Homebrew `wine-stable` cask:** disabled on 2026-09-01 for failing Gatekeeper, and it lags behind.

## Consequences
- Fast setup (Wine 11.21 installs in about 25 s).
- No msync in the default runtime: the `MSYNC=1` bottle flag only takes effect with a CrossOver-source build.
- We depend on a third party's release cadence and asset naming. `gh_asset` matches assets by regex, so a
  rename breaks `runtime install` loudly, not silently.
