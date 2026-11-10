# Architecture

Decant runs x86-64 Windows programs on Apple Silicon Macs. It's a thin orchestration layer over four
external pieces, plus one piece of its own (the fix system). This document describes **what exists**;
the reasons for each choice are in [docs/adr/](adr/README.md). Keep both up to date (see
[CLAUDE.md](../CLAUDE.md)).

## Layers

```
 Windows .exe (x86/x64, DirectX)
   │
   │  Rosetta 2 ─ translates x86-64 CPU code (whole Wine process runs as x86_64)
   │
   ├─ Wine runtime ─ Win32/NT API on macOS      runtimes/<name>/        ADR-0002, ADR-0012
   │    prebuilt Gcenx (no DXMT) or self-built CrossOver FOSS (DXMT + msync)
   │    └─ new WoW64: 32-bit apps inside a 64-bit process (macOS has no 32-bit processes)
   │
   ├─ Graphics backend ─ DirectX → Metal         backends/<name>/        ADR-0003, ADR-0004
   │    dxmt      builtin DLLs, DX10/11 → Metal           (runtime clone overlay; needs a
   │              runtime whose winemac.so exports macdrv_* — ADR-0011)
   │    d3dmetal  builtin DLLs, DX11/12 → Metal (Apple)   (runtime clone overlay)
   │    dxvk      native DLLs, DX9-11 → Vulkan → MoltenVK (copied into the prefix)
   │    wined3d   Wine's own OpenGL path
   │
   ├─ Compatibility fixes ─ per-app recipes      fixes/*.fix             ADR-0005, ADR-0006
   │    args / env / DLL overrides / registry / launch shims / installers
   │
   ├─ Input ─ controllers via Wine's winebus (SDL2 / IOHID → XInput, DirectInput)   ADR-0018
   │
   └─ Library ─ games from store integrations + programs.tsv   integrations/*   ADR-0010
        decant library / play / stop  →  the app's Library grid
```

## Components

| Component | Path | Role |
|---|---|---|
| CLI | `bin/decant` | **All logic.** Single bash 3.2 script, no dependencies beyond macOS. ADR-0001 |
| App | `app/` | SwiftUI shell. Reads `bottle.conf` and `programs.tsv` directly, and performs every action by running the CLI. |
| Fix recipes | `fixes/*.fix` | App-specific knowledge as data. |
| Store integrations | `integrations/<id>` | Read-only plugins that list a store's installed games ([docs/integrations.md](integrations.md)). ADR-0010 |
| Elevation helper | `shim/decant-elevate.c` → `share/decant-elevate64.exe` | "Run as administrator": `ShellExecuteEx` with `runas`. ADR-0013 |
| Launch shim | `shim/decant-shim.c` → `share/decant-shim{64,32}.exe` | Generic Windows program that injects args into child processes we can't otherwise reach. ADR-0006, ADR-0007 |
| Wine build | `scripts/build-wine.sh`, `patches/<mode>/` | Optional: upstream or CrossOver-source Wine, with Decant's small patches applied, imported as a runtime. ADR-0012, ADR-0015 |
| Tests | `tests/run.sh`, `tests/live.sh` | Fake-Wine suite and real-Wine suite. ADR-0008 |

## On-disk layout (`$DECANT_HOME`, default `~/Library/Application Support/Decant`)

```
runtimes/<name>/{bin,lib,share}          a Wine build (bin/wine, lib/wine/{x86_64,i386}-{windows,unix})
runtimes/<name>+<backend>/               APFS clone of <name> with a builtin-DLL backend overlaid
backends/<name>/                         extracted backend release (+ .decant-version)
bottles/<name>/bottle.conf               KEY=VALUE settings (see README "Performance knobs")
bottles/<name>/programs.tsv              label<TAB>path<TAB>default args
bottles/<name>/.dxvk-dlls                DXVK DLLs currently copied into the prefix
bottles/<name>/prefix/                   the WINEPREFIX (drive_c, dosdevices, registry)
bottles/<name>/logs/<ts>-<pid>.log       one log per launch, header lists the effective env
bottles/<name>/logs/installer-latest.log → prefix/drive_c/decant-logs/<ts>-<name>.log (installer's own log)
bottles/<name>/prefix/drive_c/decant-stage/  installers staged by `run --admin`
bottles/<name>/cache/                    DXVK state cache, DXMT shader cache
bottles/<name>/.fixes/<id>.reg           hash of the recipe's REG lines last applied
fixes/<id>.fix                           user recipes; override built-ins with the same id
decant.conf                              Decant-wide settings: DEFAULT_BOTTLE (ADR-0016)
                                         (`decant setup` creates bottles/games and sets it, ADR-0023)
downloads/                               cached release tarballs
```

## What `decant run <bottle> <target> [args]` does

1. **Resolve the target.** A saved label in `programs.tsv` becomes its path plus its default args.
2. **Match fixes.** Find every enabled recipe whose `MATCH` lists the target's basename
   (case-insensitive, Windows or Unix path). `FIXES_DISABLED` and `DECANT_NO_FIXES=1` turn recipes off.
3. **Apply fixes** (`fix_apply`):
   - `SHIM` lines are resolved against the target's directory. Each matching file is checked: if it isn't
     already our shim, it's moved to `<name>.decant-real.exe` and replaced by the 32- or 64-bit shim
     (chosen from its PE header). Then the `<name>.decant-shim` sidecar is regenerated. This is what makes
     the fix survive app self-updates.
   - `REG` lines are applied with `wine reg add`, but only when they changed since the last time.
   - `ARGS`, `ENV` and `DLLOVERRIDES` are collected into `FIX_ARGS`, `FIX_ENV` and `FIX_DLL`.
4. **Build the environment** (`bottle_env`): `BACKEND=auto` is resolved first (ADR-0019): on a runtime
   with the macdrv exports, D3DMetal if imported, else DXMT, owns DXGI + DX10-12, and wined3d keeps DX9
   and older, DirectDraw and OpenGL. Without the exports it's DXVK, else wined3d. `dxvk_sync` makes the
   prefix hold DXVK's DLLs exactly while the result is DXVK. Then: runtime choice (cloned with the backend overlay where needed),
   backend DLL overrides and tuning env, bottle flags, `EXTRA_ENV`, and finally the fix contributions,
   which win.
5. **Launch** `wine <target> <fix args, deduplicated> <user args>` in the background, with output going to
   a new log file. The launch uses a subshell that ignores SIGHUP, never `nohup`: SIP-protected binaries
   lose `DYLD_*`, which runtimes need to find their bundled dylibs. Every launch also sets
   `CX_REPORT_REAL_USERNAME=1` (ADR-0012) and `DECANT_WOW64_RESERVE_TOP=1`, which makes patched CrossOver
   ntdll keep `0xFFFD0000` reserved in large-address-aware 32-bit processes, as upstream Wine does
   (`patches/crossover/0002`, ADR-0020).

The shim, when the app later starts the shimmed child, reads its sidecar, appends `inject=` args unless
a `skip=` substring is already on the command line, applies `env=`, then starts `<name>.decant-real.exe`
and waits for it, returning the real binary's exit code.

## What `decant library` / `play` do

`library` runs every integration's `detect` and `games` for each bottle, adds the bottle's
`programs.tsv` entries (except store launchers such as `steam.exe`), and marks rows running by matching
each row's `match` against one lower-cased `ps` snapshot. Output: `bottle key name source folder image running`.
`play <bottle> <key>` looks the row up and calls `cmd_run` with its target and args. A Steam game
becomes `steam.exe -noverifyfiles -cef-disable-gpu -applaunch <appid>` once the Steam recipe has added
its args, and Steam starts the game as its child, inside the same bottle environment. `stop` sends
SIGTERM to processes whose command line contains `match`.

## Run as administrator (`run --admin`, `repair`)

`run --admin` refuses to run if the bottle has files not owned by the user (that's `repair`'s job). It
clears read-only bits in `drive_c`, and stages an outside installer into `C:\decant-stage\<folder>-<name>`
(APFS clone, quarantine stripped; only `<stem>*` files from shared folders). It then runs
`share/decant-elevate64.exe <windows path> args`, which re-launches the target with `ShellExecuteEx`
verb `runas` so Wine grants the full admin token. `repair` fixes read-only bits and quarantine, and for
foreign-owned files prints the single root command (`--print-sudo`), which the app runs through macOS's
administrator prompt. Decant itself never runs as root (ADR-0013).

## Installer logs and activity (`status`, `logs`, `diagnostics`)

Before launching an exe, `installer_log_args` checks for Inno Setup (`/LOG=`) or MSI (`/l*v`) and,
unless the user passed one, adds a log file in `C:\decant-logs`, linked as `logs/installer-latest.log`.
`status` lists the bottle's Windows processes by matching their open files (`lsof -Fn`) against the prefix
(logical and physical path), flags Wine's own services (`SYSTEM_PROCS`), and decides busy, waiting or
stopped from CPU (≥ 5%) and installer-log freshness (< 15 s). `diagnostics` zips summary, settings and the
newest logs (ADR-0014).

## Game discovery (`program scan`)

For hand-installed games. It looks under `Program Files`, `Program Files (x86)`, `C:\Games`, `C:\GOG Games`
and `users/*/AppData/Local/Programs`, one install folder at a time, and skips:
- Wine's stand-in programs and shared folders (`SCAN_SKIP_DIRS`);
- folders owned by a store integration's launcher;
- folders that already have a library entry;
- console executables (PE subsystem ≠ GUI) and helper names (`SCAN_SKIP_EXES`).

Each remaining folder gets one exe: the one whose name matches the folder, then a shallow path, then the
largest file. `--since` keeps only folders containing files newer than an installer's start time.

## Invariants (tests enforce these)

- The base runtime under `runtimes/<name>` is never modified; backends go into `+<backend>` clones.
- DXMT and D3DMetal are never selected or accepted on a runtime that can't present with them (ADR-0011, ADR-0019).
- Large-address-aware 32-bit processes never get a free block of 2 GB or more on a patched CrossOver
  runtime (ADR-0020; live test "FreeArc's search ends").
- `BACKEND=auto` is resolved at every launch, never written back to `bottle.conf` (ADR-0019).
- Integrations only report; launching always goes through `cmd_run` (so recipes apply).
- Leaving the DXVK backend, explicitly or because `auto` now resolves elsewhere, restores Wine's own DLLs in the prefix.
- Shim install is idempotent: relaunching never replaces the real binary with the shim.
- An app update that overwrites a shim is detected, and the new file becomes the real binary.
- Disabling a fix reverts all its shims.
- `bin/decant` contains no app-specific logic; app knowledge (installers, workarounds) lives only in `fixes/`.
  The one exception is the `install-steam` command alias, which just forwards to `install <bottle> steam`.
