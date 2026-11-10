# 0007. Commit prebuilt shim binaries next to their source

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Building `decant-shim` needs mingw-w64, a 1.4 GB toolchain. Users running Decant shouldn't need it.

## Decision
`share/decant-shim64.exe` and `share/decant-shim32.exe` are committed. They are rebuilt from
`shim/decant-shim.c`. Any change to the source must include the rebuilt binaries in the same commit.
Shim identity is checked by byte comparison, so a stale binary is caught: existing installs get
re-shimmed with the new one on their next launch.

## Alternatives considered
- **Build on first use:** forces every user to install mingw.
- **Download from a release:** adds a network dependency and a release process we don't have yet.

## Consequences
- About 36 KB of binaries in the repo. The diff is opaque, so review the C source.
- When CI exists, it should rebuild and fail if the committed binaries differ.
