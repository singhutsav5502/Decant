# 0012. Build CrossOver's FOSS Wine for DXMT, linking prebuilt x86_64 libraries

- **Status:** Accepted; Mono consequence superseded by [0017](0017-bundle-wine-mono-in-built-runtimes.md)
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
ADR-0011 found that DXMT can't present on prebuilt Gcenx Wine: `winemetal.so` `dlsym()`s the
`macdrv_functions` table, and Gcenx's `winemac.so` has those symbols stripped, so no re-export or
binary patch is possible. DXMT's own install guide requires "a FOSS CrossOver Wine 24+ built from the
sources", and no prebuilt one is published. CrossOver 26.1.0's source (Wine 11.0) exports
`macdrv_functions` from `dlls/winemac.drv/d3dmetal.c`, and it adds msync.

Building normally on Apple Silicon needs an x86_64 Homebrew in `/usr/local`, which requires an admin
password, plus about 1 GB of x86_64 dependencies.

## Decision
`scripts/build-wine.sh crossover <version>` builds without an x86_64 Homebrew:
- **Tools** (bison ≥ 3, mingw-w64) and **headers** (freetype, gnutls, SDL2) come from the normal arm64
  Homebrew. Headers are arch-independent.
- **x86_64 libraries** to link against are cloned from an installed prebuilt runtime's `lib/`, and then
  bundled into the result, so it's self-contained.
- Everything is compiled as x86_64 under Rosetta (`arch -x86_64`, `clang -arch x86_64`).

Workarounds found while doing this, all encoded in the script with comments:

| Problem | Fix |
|---|---|
| Wine 11's macOS OpenGL needs EGL | `--without-opengl` (DXMT and DXVK don't use GL) |
| configure parses `otool -L` and records garbled sonames (`"\tlibfreetype.dylib (compatibility…)"`) for bare-named libs | pin SDL2 via `ac_cv_lib_soname_SDL2`; rewrite the freetype, gnutls and vulkan sonames in `config.h` after configure (passing them as `ac_cv_*` broke configure) |
| `pipe2` is declared in the SDK but missing from libSystem at runtime, so ntdll calls address 0 at startup | `#undef HAVE_PIPE2` in `config.h` |
| build-time tools (sfnt2fon) can't find bare-named dylibs, and `DYLD_*` doesn't survive `make`'s SIP-protected `/bin/sh` | clone the dylibs into the build directory (dyld searches the cwd) |
| `wineserver` and `winebus.so` link `libinotify.dylib` directly | rewrite those links to `@executable_path` / `@loader_path`, then re-sign ad hoc |
| no Wine Gecko or Mono bundled | reuse the prebuilt runtime's copy when the version matches (Gecko 2.47.4 does; Mono 10.4.1 ≠ 11.3.0) |

Runtime-side changes in `bin/decant` from the same investigation:
- **Background launches don't use `nohup`.** It's SIP-protected, so macOS strips `DYLD_*` from it and
  its children, and runtimes find their bundled dylibs through `DYLD_FALLBACK_LIBRARY_PATH`.
- **`CX_REPORT_REAL_USERNAME=1` for every launch.** CrossOver reports every user as `crossover`, while
  ntdll uses `$USER` for `C:\users\<name>`. Without this, apps lose saved logins and saves when a bottle
  changes runtime.
- `runtime_supports_dxmt` checks for the exported `_macdrv_functions` symbol, and `default_runtime`
  prefers a DXMT-capable runtime.

## Alternatives considered
- **x86_64 Homebrew in `/usr/local`:** the documented way, but it needs an admin password and a second
  package manager.
- **Re-export the symbols from Gcenx's `winemac.so`:** impossible, because they're stripped, not just hidden.
- **Patch DXMT to find the window's NSView without Wine's help:** a fork of a C++ project with its own
  toolchain, to maintain forever.
- **Rebuild upstream WineHQ with `-fvisibility=default`:** upstream has no exported `macdrv_functions`
  table, which is what DXMT looks up.

## Consequences
- Verified 2026-11-04: 9 Kings (Unity 6, DX11) **renders and plays on DXMT** through Steam on Apple M5,
  with msync active. Frame rate was 60 FPS, the same as DXVK, because both hit the display cap; heavier
  games still need measuring.
- Builds take about 10 minutes on an M5 once dependencies are in place, and depend on a prebuilt runtime
  being installed first (the script installs one if missing).
- No OpenGL, GStreamer or Kerberos in this runtime: no wined3d fallback, no H.264 video in some games,
  and no Kerberos auth. .NET apps prompt to download Wine Mono 10.4.1.
- CrossOver's source changes with each release. Re-check this table when bumping the version.
