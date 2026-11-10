# Changelog

All notable changes to Decant. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow `DECANT_VERSION` in `bin/decant`. Rules: [ADR-0009](docs/adr/0009-decision-records-and-changelog.md).

## [Unreleased]

## [0.9.0] - 2026-11-10
First public release: MIT licence, `decant setup`, `BACKEND=auto`, and a drag-install DMG.
### Added
- **`decant setup`**: the recommended setup in one re-runnable command (ADR-0023). It installs a prebuilt
  Wine, optionally builds CrossOver Wine 26.1.0 (`--build-wine`), installs DXMT and DXVK, imports D3DMetal
  with `--gptk <dir>`, and creates the default bottle `games` (BACKEND=auto, win10, msync, AVX). Steps
  already done are skipped; existing bottles and a user-chosen default are left alone. The app has a
  **Set Up Recommended** button under Components, and the README quick start uses it.
- **Open-source release prep** (ADR-0022): MIT `LICENSE` and `patches/LICENSE` (LGPL-2.1-or-later for the
  Wine patches). The README has a Licence section. Docs and trimmed logs refer to the
  Hades II installer as an Inno Setup + FreeArc installer instead of by its source. This includes a
  wording-only edit to accepted ADRs 0019 and 0020 (no decision changed).
- **Branded app**: Decant.app has a display name, an app icon, version and build number from
  `DECANT_VERSION`, and a copyright line stating Decant isn't affiliated with Valve, Apple, CodeWeavers or
  publishers.
- `docs/investigations/2026-11-04-hades2/`: the record of the Hades II / FreeArc installer / DX12 investigation. It
  holds what each throwaway bottle was for and showed, the root causes and dead ends, the probe sources and
  results, and trimmed launch and installer logs (raw logs not kept; paths and user name scrubbed).
- **`BACKEND=auto`, the new default** (ADR-0019): one runtime serves every API, decided at each launch
  from what's installed. On a CrossOver-based runtime, D3DMetal (if imported, else DXMT) owns DXGI and
  DirectX 10-12, Wine's wined3d keeps DirectX 9 and older, DirectDraw and OpenGL, and Vulkan goes to
  MoltenVK. On runtimes that can't present with Metal it's DXVK. Importing D3DMetal upgrades every auto
  bottle on its next launch; the launch log names the resolved backend.
- `fixes/hades2.fix` and [docs/fixes/hades2.md](docs/fixes/hades2.md): Hades II runs from `Ship\Hades2.exe`
  on `crossover-26.1.0` with D3DMetal (via `auto`). `Release\Hades2.exe` is a development build that can't find its
  Content folder, and `F10.exe` is the game's bug reporter, not the game.
- ADRs for decisions made in 0.7.0–0.8.0: the default bottle and `decant.conf` (ADR-0016), bundling
  Wine Mono in self-built runtimes (ADR-0017, which supersedes part of ADR-0012) and controller
  support through Wine's winebus (ADR-0018). ARCHITECTURE.md links them.
### Changed
- D3DMetal, like DXMT, is refused on runtimes without the macOS-driver exports (it fails to initialise there).
### Fixed
- **Release builds no longer embed the builder's source path.** The app's dev-run fallback for finding
  `bin/decant` uses `#filePath`, which baked the absolute path of the build machine's checkout (including
  the user name) into `Decant.app`. It is now compiled into debug builds only, so the release binary holds no build-machine paths.
- **FreeArc-based installers no longer freeze on CrossOver runtimes** (ADR-0020).
  `unarc.dll` searches for its largest memory block with a 32-bit `(lo+hi)>>1` that never ends when a 2 GB
  reservation succeeds, and CrossOver's Wine 11.0 granted one where upstream Wine and Windows don't.
  `patches/crossover/0002` keeps `0xFFFD0000` reserved in large-address-aware 32-bit processes (opt-in
  through `DECANT_WOW64_RESERVE_TOP=1`, which every launch now sets). This was the only reason to keep a
  separate staging+cxgate bottle for installers.
- **DXVK on self-built CrossOver runtimes:** `build-wine.sh` linked Wine's Vulkan to the Khronos loader,
  which hides MoltenVK because CrossOver's winevulkan doesn't ask for portability drivers. Every DXVK game
  failed with `VK_KHR_surface not supported` (Silksong, 9 Kings). It now links `libMoltenVK.dylib`
  directly. Repair an existing build by rebuilding it, or by replacing its `lib/libvulkan.1.dylib` with
  `lib/libMoltenVK.dylib`.
- `decant run` with a Windows path (`C:\...\game.exe`, as store integrations and saved labels use) now
  starts in the exe's folder, as unix paths already did. Before, Wine's working directory was left to chance.
- `program scan` treats a roman numeral in the folder name as digits ("Hades II" matches `Hades2.exe`).
  Before, no name matched, so the scan fell back to file size and picked Hades II's 9 MB `F10.exe` crash
  reporter as the game.

## [0.8.0] - 2026-11-04
### Added
- `decant controllers <bottle>` (app: **Game Controllers**): lists the gamepads macOS sees, with name,
  transport and IDs, then opens Wine's Game Controllers panel (joy.cpl) to test buttons. Both runtimes
  ship winebus with SDL2 and IOHID backends, plus XInput/DirectInput.

## [0.7.0] - 2026-11-04
### Added
- **Default bottle**: `decant bottle default [name]`, `bottle create --default`, a marker in
  `bottle list` and `doctor`. The only bottle is the default automatically. App: ★ in the sidebar,
  "Make Default Bottle", and Add Game / Install Steam / Open Steam use the default.
- **`patches/crossover/`**, applied by `build-wine.sh` (ADR-0015). The first patch makes shell32's
  hard-coded "crossover" profile name honour `CX_REPORT_REAL_USERNAME`, so a bottle has one profile
  (`C:\users\<you>`).
- `build-wine.sh` downloads the exact Wine Mono version the build expects (from dl.winehq.org) when no
  local copy matches.

### Changed
- Recommended setup: one `games` bottle on the DXMT-capable runtime, set as default. Verified with Steam
  carried over (still signed in) and 9 Kings playing on DXMT.
### Fixed
- **Game discovery offered bundled tools as the game.** `program scan` now skips bundled-prerequisite
  subfolders (`_Redist`, `_CommonRedist`, `__Installer`, `DirectX`, `*prereq*`). An install that left
  only an uninstaller and redistributables (e.g. an installer that never finished unpacking) used to
  suggest `_Redist/QuickSFV.EXE`; it now finds nothing, which is the truth.

## [0.6.0] - 2026-11-04
### Added
- **Installer logs by default**: Inno Setup gets `/LOG=C:\decant-logs\…`, MSI gets `/l*v` (also with
  `--admin`), unless you pass your own; `logs/installer-latest.log` links the newest. ADR-0014.
- **`decant status <bottle>`**: Windows processes in the bottle (mapped through their open files), with
  CPU, elapsed time and log freshness, and a verdict: *working*, *waiting for you* or *stopped*.
- `decant logs --installer/--follow`; **`decant diagnostics`** zips logs, settings and status to the Desktop.
- App: **Activity** panel in bottle settings and in Add Game's installer step, with Open Log / Show Logs /
  Export Diagnostics.

### Fixed
- `diagnostics` (new) could exit silently under `pipefail` when a log glob matched nothing. Added the
  `newest` helper.

## [0.5.0] - 2026-11-04
### Added
- **Run as administrator** (`decant run --admin`; in the app: an installer switch in Add Game, on by
  default, plus "Run as Administrator" in bottle settings and the library menu). It stages the installer
  into the bottle (APFS clone, quarantine stripped), clears read-only files, and launches through
  `decant-elevate64.exe` (`ShellExecuteEx` "runas"), which gets Wine's full admin token. Verified in
  real Wine: limited token normally (type 3), full token with `--admin` (type 2). ADR-0013.
- `decant repair <bottle>` (app: "Repair Permissions"): fixes read-only and quarantine without a
  password. For files owned by another user it shows the single `chown` that needs root, which the app
  runs through macOS's administrator prompt.

## [0.4.0] - 2026-11-04
### Added
- **DXMT-capable runtime**: `scripts/build-wine.sh crossover 26.1.0` builds CrossOver's FOSS Wine 11.0
  (exports `macdrv_functions`, has msync) without an x86_64 Homebrew, using arm64 Homebrew tools and
  headers and linking the x86_64 libraries from a prebuilt runtime (ADR-0012). 9 Kings renders and plays
  on DXMT through Steam (Apple M5).

### Changed
- `default_runtime` prefers a DXMT-capable runtime instead of the alphabetically first one.
- `runtime_supports_dxmt` checks for the exported `_macdrv_functions` symbol that DXMT looks up.
- **Game discovery** (`program scan`, the app's "Find installed games"): returns one best exe per install
  folder. It skips Wine's stand-in programs, Common Files, store-owned folders (e.g. Steam's), folders
  already in the library, console tools, and helpers (uninstallers, crash reporters, updaters,
  redistributables). It also searches `C:\Games`, `C:\GOG Games` and per-user app folders. `--all` lists
  every candidate. `--since <epoch>` limits results to folders changed since then; the app's installer
  flow uses this. On the Steam bottle, the noise went from 35 entries to 0.

### Fixed
- Background launches no longer use `nohup`. It's SIP-protected, so macOS stripped `DYLD_*`, and a
  runtime whose `wineserver` links a bundled dylib (libinotify) couldn't start.
- `CX_REPORT_REAL_USERNAME=1` on every launch, so bottles keep the same `C:\users\<name>` (saved Steam
  logins, game saves) when switched to CrossOver-based Wine.
- **Cold-start launches lost the runtime's library path.** `decant run`/`play` started Wine through
  `/usr/bin/nohup`, which macOS SIP strips `DYLD_*` from, so a fresh `wineserver` failed with
  `Library not loaded: libinotify.dylib` (CrossOver-built runtimes) unless one was already running.
  Launches now detach with a HUP-ignoring subshell `exec`, which keeps the environment.

## [0.3.0] - 2026-11-04
### Added
- **Library**: `decant library|play|stop` and `library add|remove` combine store games and your own `.exe`
  games, with running detection.
- **Store integration plugins** (`integrations/<id>`, ADR-0010). The first is `steam`: it reads
  `libraryfolders.vdf` and `appmanifest_*.acf`, shows cover art, and launches with `-applaunch`.
  `decant integration list`.
- App: a **Library** grid as the main screen (cover art, Play/Stop, running badge, search, context
  menu), **Add Game…** (game exe, or installer → find installed programs), and **Open Steam** /
  **Install Steam**.
- `runtime list` reports DXMT capability. `doctor` shows it per runtime.

### Changed
- **Default backend depends on runtime capability** (ADR-0011, superseding ADR-0004's default). DXMT is
  refused on runtimes whose `winemac.so` doesn't export the macdrv metal-view symbols (all prebuilt
  Gcenx builds), and those bottles default to DXVK. The app's new-bottle sheet has "Automatic".
- `scripts/build-wine.sh` builds with `-fvisibility=default` and reports DXMT capability (not yet run).

### Fixed
- Steam games exiting about 3 s after launch: DXMT couldn't present on prebuilt Wine. The Steam bottle
  now uses DXVK, and 9 Kings runs.
- SIGPIPE aborts under `pipefail`: `play` could quit silently, and running-game detection could miss
  games when the process list was large. Pipeline helpers added, and the rule is documented.

## [0.2.0] - 2026-11-04
### Added
- **Compatibility fix recipes** (`fixes/*.fix`): per-app `ARGS`, `ENV`, `DLLOVERRIDES`, `REG` and `SHIM`,
  matched by exe name on every `decant run`. User recipes in `$DECANT_HOME/fixes` override built-ins
  (ADR-0005).
- `decant install <bottle> <recipe>`: recipes can define `INSTALL_URL`, `INSTALL_ARGS` and `PROGRAM`.
  `install-steam` is now an alias.
- `decant fix list|show|check|status|enable|disable|revert`, and a `FIXES_DISABLED` bottle key.
  `DECANT_NO_FIXES=1` bypasses all recipes.
- **`decant-shim`**: a generic, sidecar-configured launch shim (x64 + x86) that injects args into child
  processes and survives app self-updates (ADR-0006, ADR-0007).
- `fixes/steam.fix`: Steam renders and signs in (black CEF windows and broken login polling fixed).
  Case notes in `docs/fixes/steam.md`.
- Test suites: `tests/run.sh` (fake Wine, 45 checks) and `tests/live.sh` (shim inside real Wine) (ADR-0008).
- App: a "Compatibility fixes" section with a per-bottle switch for each recipe.
- Docs: `docs/ARCHITECTURE.md`, ADRs 0001–0009, `docs/fixes/`, `CLAUDE.md`.

### Changed
- `install-steam` no longer hard-codes anything; `fixes/steam.fix` supplies the installer and flags.
- Saved programs (`programs.tsv`) take an optional third column of default args.

### Removed
- The Steam-only `steamwebhelper` wrapper and the `steam_wrap` code path, both replaced by the recipe and
  the generic shim. Existing bottles were migrated by restoring `steamwebhelper_real.exe` →
  `steamwebhelper.exe`; the next launch shims it with `decant-shim`.

## [0.1.0] - 2026-11-03
### Added
- `bin/decant` CLI: runtimes (Gcenx Wine), backends (DXMT, DXVK, bring-your-own D3DMetal), bottles,
  programs, logs, `doctor`, `install-steam`.
- Builtin-DLL backends via APFS-cloned runtimes (ADR-0003). DXVK DLLs are swapped in and out of the
  prefix (ADR-0004).
- Metal tuning: DXMT shader cache and MetalFX, MoltenVK flags, msync/AVX/HUD/Retina switches.
- SwiftUI `Decant.app` (ADR-0001), `scripts/build-wine.sh`.
