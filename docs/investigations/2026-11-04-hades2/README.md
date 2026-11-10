# Investigation: Hades II (Inno Setup + FreeArc installer), DX12, and one bottle for everything

**Dates:** 2026-11-04 to 2026-11-05 · **Hardware:** Apple M5, macOS 26.6 · **Outcome:** one bottle, `games`, on
`crossover-26.1.0` with `BACKEND=auto`, runs the FreeArc installer, Hades II (DX12), Steam, 9 Kings and Hollow
Knight Silksong, all verified on screen.

This folder keeps the findings and evidence from the throwaway bottles used along the way: `fg-test`, `fg-repro`,
`fg-d3dm` and `fg-verify`, removed on 2026-11-05. `fg-cxgate` and `games` remain. The raw logs (about 2.3 GB,
mostly `+loaddll`/`+relay` traces) weren't kept. What's here are excerpts, the probe sources and results, and
the earlier analysis notes. Paths are shortened to `~`, and the user name reads `<user>`.

The decisions that came out of it:
- [ADR-0019](../../adr/0019-auto-backend-best-layer-per-api.md): `BACKEND=auto`, the best layer per API, decided at launch.
- [ADR-0020](../../adr/0020-wow64-laa-top-reservation.md): reserve `0xFFFD0000` in large-address-aware 32-bit
  processes (`patches/crossover/0002`).
- [docs/fixes/hades2.md](../../fixes/hades2.md): the Hades II recipe and case notes.
- `scripts/build-wine.sh` links MoltenVK directly (CHANGELOG, Unreleased).

## The bottles

| Bottle | Runtime / backend | What it was for | What it showed | Fate |
|---|---|---|---|---|
| `games` | crossover-26.1.0 (then dxvk; now `auto`) | Steam, the main bottle | installer froze (finding B); later the end-to-end check of every fix | kept, default |
| `fg-test` | staging-11.21, wined3d | first installer attempts | installer crash in `wow64cpu` (finding A); memprobe baselines | removed |
| `fg-repro` | staging-11.21, wined3d | reproduce A outside the installer | `repro-gate`, `repro-gate2`, `repro-smc`: all PASS, no crash reproduced | removed |
| `fg-cxgate` | staging-11.21-cxgate (CrossOver's `wow64cpu.dll` swapped in) | swap test for A | **installer finished**, and Hades II was installed here | kept |
| `fg-d3dm` | clone of fg-cxgate on crossover-26.1.0 + D3DMetal | first DX12 render of Hades II | D3DMetal works only on CrossOver; Hades II renders | removed |
| `fg-verify` | clone of fg-cxgate (staging-cxgate) | tests of the per-program runtime switch, later dropped; DXVK Vulkan diagnosis | Vulkan loader trace; DXVK finds the M5 when CrossOver loads MoltenVK directly | removed |

`fg-d3dm` and `fg-verify` were APFS clones of `fg-cxgate`, so their early logs are copies of its logs. The
excerpts in `launch-logs/` note where a log repeats one from an earlier bottle.

## Problems and root causes, in the order they were found

### 1. Installer crash on staging 11.21 (finding A)
The GUI thread of `setup.tmp` faulted at `wow64cpu+0x1135` (`movl cs32_sel(%rip),%edx` in `syscall_32to64`),
reading `0x2EC5`, which is the instruction's own displacement. The 64-bit gate code ran in 32-bit mode
under Rosetta. Swapping in CrossOver's `wow64cpu.dll` (runtime `staging-11.21-cxgate`) avoided it, and
CrossOver ships the same `wow64cpu.dll`. The synthetic gate stress tests didn't reproduce the fault on
either runtime (`prior/fx-gate-findings.txt`, `prior/repro-gate2-results.txt`). Report draft:
`prior/upstream-bug-report.md`.

### 2. Installer freeze on CrossOver 26.1 (finding B): root cause found 2026-11-05
- **Symptom:** stuck at about 34 MB / 11 files, `setup.tmp` at 100% CPU; "Exit Setup" had no effect.
- **Earlier hypothesis, wrong:** free RAM wrapping in 32-bit maths (`prior/downstream-brief.md`). The
  memprobe results show the same `GlobalMemoryStatusEx` and `AvailablePages` on every runtime
  (`results/*memprobe32*.txt`).
- **Cause:** `winedbg` on the frozen process (`results/20261105-games-winedbg-setup.tmp-backtraces.txt`):
  thread `06c0` spins in FreeArc's `unarc.dll` at `+0xaaf4`, inside `NtFreeVirtualMemory`. The disassembly
  (`results/unarc.dll-largest-block-search.asm`, `0x6108a904`) is a binary search for the largest
  reservable block, `mid = (lo + hi) >> 1` in 32 bits. If `reserve(0x7FFFFFFF)` succeeds, `mid` wraps around
  and shrinks to 0, and it never ends.
- **Why only CrossOver:** `probes/bsprobe.c` copies the loop and gave the same result on every run:
  - CrossOver grants the 2 GB reservation (largest free block 2048 MB at `0x7FFE1000`, search hangs).
  - Staging refuses it (1970 MB, ends in 32 steps): `results/20261105-*-bsprobe.txt`.
  - `probes/vmmap32.c` shows why: upstream Wine 11.21 has a 64 KB block committed at `0xFFFD0000`, and
    CrossOver's Wine 11.0 doesn't (`results/20261105-*-vmmap32.txt`).
  - `probes/tebprobe.c` rules out the TEB/PEB (`results/20261105-*-tebprobe.txt`).
- **Fix:** ADR-0020.
- **Verified:** the installer completed in `games` (5,953 files).
- **So what made `fg-cxgate` work** was staging's address-space layout, not the swapped `wow64cpu.dll`.

### 3. "Launching F10 crashes"
- **The wrong program:** the library entry pointed at `Release\F10.exe`, Supergiant's bug reporter
  ("F10" is the game's codename). `program scan` picked it because neither name matched the folder
  "Hades II", so the larger file won. Fixed: names now treat roman numerals as digits.
- **The wrong build:** `Release\Hades2.exe` is a development build with a hard-coded `..\..\..\` to its
  Content folder, which lands on `C:\Content`. Its gamepad check then asserts and starts F10.exe.
  `Ship\Hades2.exe` is the shipping build.
- **Related fix:** `probes/argprobe.c` showed the command line was quoted correctly. Along the way,
  `decant run` with a Windows path was changed to start in the exe's folder.

### 4. DX12: "No available D3D12 adapter found"
Hades II is DX12 only. Wine's vkd3d over MoltenVK gave no usable adapter, and D3DMetal failed on staging
(`d3d12.dll failed to initialize`). On crossover-26.1.0, D3DMetal reports "AMD Compatibility Mode" and the
game renders. D3DMetal needs the same macdrv exports as DXMT, which only CrossOver's Wine has.

### 5. Silksong and 9 Kings failed after `games` moved to CrossOver
DXVK reported `Required Vulkan extension VK_KHR_surface not supported`. `VK_LOADER_DEBUG` showed the Khronos
loader hiding MoltenVK, because CrossOver's winevulkan never asks for `VK_KHR_portability_enumeration`.
- **Dead ends:**
  - Copying `share/vulkan/icd.d` into the runtime: CrossOver's Wine searches
    `lib/wine/x86_64-unix/vulkan/icd.d`, not `share/vulkan/icd.d`.
  - Exporting `VK_DRIVER_FILES`: the loader then found MoltenVK but still filtered it out.
- **Fix:** load MoltenVK directly. `build-wine.sh` now prefers `libMoltenVK.dylib`; the installed
  runtime's `libvulkan.1.dylib` was replaced with MoltenVK.

### 6. One bottle per setup
- **Drafted, then dropped:** per-program and per-recipe runtime/backend overrides. You'd have to pick a
  setup per game, and two Wine versions can't share a prefix's wineserver.
- **Replacement:** `BACKEND=auto` (ADR-0019). D3DMetal, or DXMT without it, owns DXGI and DX10-12; wined3d
  keeps DX9 and older and OpenGL; MoltenVK serves Vulkan.
- **Why DXVK isn't in the mix:** DXVK-macOS ships only `d3d10core`/`d3d11`, so on a Metal-capable runtime it
  adds nothing.

### 7. The installer froze again after the fix
It was launched from `dist/Decant.app`, whose bundled CLI dated from before the fix and never set
`DECANT_WOW64_RESERVE_TOP`. You can tell from the launch log header: it has no `# backend:` line. `make app`
fixed it. Lesson: rebuild the app after changing `bin/decant`.

## Evidence index
- `prior/`: the notes from before 2026-11-05, as they stood after review. The `*.orig` drafts the review
  superseded weren't kept.
  - `summary.txt`, `upstream-bug-report.md` (finding A), `downstream-brief.md` (finding B plan; its RAM-wrap
    hypothesis was disproved by section 2).
  - `wow64cpu-attribution.txt`, `wow64cpu-gate-diff.txt`, `fx-gate-findings.txt`, `repro-*-results.txt`,
    `live-playbook.md`, `upstream-changes.txt`.
- `probes/`:
  - From the earlier work: `memprobe.c`, `repro-gate*.c`, `repro-smc.c`, `build.sh`, `run-probe.sh`.
  - Written on 2026-11-05: `bsprobe.c`, `vmmap32.c`, `tebprobe.c`, `argprobe.c`, and `pe_exports.py`
    (resolves ntdll offsets to export names).
  - The regression test is `tests/fixtures/largestblock.c` (live test "FreeArc's search ends").
  - Build: `i686-w64-mingw32-gcc -O1 -Wl,--large-address-aware -o x.exe x.c`.
- `results/`: memprobe runs (`20261104-*`, per bottle, plus `host.txt`); the 2026-11-05 probe outputs; the
  `winedbg` backtraces; the `unarc.dll` disassembly excerpt.
- `launch-logs/`:
  - One file per removed bottle, covering each launch: the header (runtime, env, command) and its
    error/result lines.
  - `installer/`: the Inno Setup logs of every installer run. They're identical in every bottle, because
    the bottles were cloned after these runs.

## Still open
- Finding A is a real Wine/Rosetta bug in staging's `wow64cpu`. The report draft is
  `prior/upstream-bug-report.md`, but it has no standalone reproducer yet.
- `dist/Decant.app` can fall behind `bin/decant` with no warning (section 7). A check comparing the bundled
  CLI with the repo's would catch it.
- Drop `patches/crossover/0002` once CrossOver's source includes upstream's layout.
