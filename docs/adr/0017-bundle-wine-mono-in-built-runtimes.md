# 0017. Bundle the exact Wine Mono version in self-built runtimes

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude
- Supersedes the "no Mono bundled" consequence of [ADR-0012](0012-build-crossover-wine-with-prebuilt-x86-libs.md).

## Context
ADR-0012 reused the prebuilt runtime's Gecko and Mono where the versions matched. Gecko did; Mono did not
(the CrossOver 26.1 source wants 10.4.1, the prebuilt runtime carries 11.3.0), so the self-built runtime
shipped without it. In practice the "install Wine Mono?" dialog appeared during bottle creation, blocked
`wineboot`, and looked like a hang. .NET installers and games (common in Unity/XNA titles and launchers)
then failed or prompted again.

## Decision
`scripts/build-wine.sh` reads the required version from the source (`WINE_MONO_VERSION` in `appwiz.cpl`).
If a local copy of exactly that version exists it's cloned in; otherwise the x86 tarball is downloaded
from dl.winehq.org into `$DECANT_HOME/downloads/` (resumable, verified with `tar -t`) and unpacked into
`share/wine/mono/`. A failed download is not fatal: the build continues and Wine falls back to offering
the download on first use.

## Alternatives considered
- **Disable `mscoree` (no .NET):** no dialog, but every .NET program breaks.
- **Use the newer Mono the prebuilt runtime has:** Wine only accepts the exact version it was built for.
- **Commit the tarball:** about 38 MB of third-party binary in the repo, for an optional build path.

## Consequences
- Bottles on the self-built runtime get .NET at creation with no dialog (verified: a .NET 4 test program
  runs in `games`).
- The build needs network access once per Mono version; the download is cached.
- On a CrossOver version bump, the Mono version may change and is fetched again automatically.
