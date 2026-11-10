# Hades II

Recipe: [`fixes/hades2.fix`](../../fixes/hades2.fix)
Full investigation, with evidence from every bottle used: [docs/investigations/2026-11-04-hades2](../investigations/2026-11-04-hades2/README.md)
**Verified:** 2026-11-04 · crossover-26.1.0 · bottle backend D3DMetal (Game Porting Toolkit 3.0) · macOS 26.6 · Apple M5.
The game renders on screen (checked by the user).

## Symptoms
1. **Launching the library entry opens a bug-report window, not the game.** The entry pointed at
   `Release\F10.exe`. "F10" is the game's internal codename, and `F10.exe` is Supergiant's bug reporter
   (`Hades II-F10.log`: `Report_REAL`, `Jira mode`, empty bug info).
2. **`Release\Hades2.exe` asserts, then opens F10.exe.** The game log (`C:\users\<you>\Saved Games\Hades II\Hades II.log`)
   shows `Could not open C:\Content\Scripts\checksums.txt`, then
   `Assert ... SDL2_GamePad.cpp, Line = 349, Condition = sNumSupportedGamePads > 0`.
3. **`Ship\Hades2.exe` on a staging runtime:** `No available D3D12 adapter found` / `Renderer creation failed`.
   The GPU shows as wined3d's placeholder "NVIDIA GeForce 6800".
4. **`Ship\Hades2.exe` on staging + D3DMetal:** `err:module:loader_init "d3d12.dll" failed to initialize`.

## Cause
- (1) `program scan` matched no exe name to the folder "Hades II", because of the roman numeral, so it
  picked the largest GUI exe, which was `F10.exe` (9.2 MB). Fixed in `bin/decant`: names now treat roman
  numerals as digits.
- (2) `Release\Hades2.exe` is a development build. It finds Content through a hard-coded `..\..\..\` from
  its own folder, which lands on `C:\`. This has nothing to do with the working directory: it fails the
  same way with CWD set to the exe's folder. `Ship\Hades2.exe` is the shipping build and finds `..\Content`.
  `program scan` still prefers `Release\` because the file is bigger, so point the entry at `Ship\` by hand.
- (3) The game is DirectX 12 only. Wine's own d3d12 (vkd3d over MoltenVK) exposes no usable adapter here.
- (4) GPTK's D3DMetal needs the macOS driver hooks that CrossOver's Wine exports. Staging Wine doesn't have them.

## Fix
```bash
decant backend install d3dmetal "/Volumes/Evaluation environment for Windows games 3.0"
decant program add <bottle> "Hades II" 'C:\Program Files\Hades II\Ship\Hades2.exe'
```
The bottle has to be on a CrossOver-based runtime (`yes` in `decant runtime list`) with `BACKEND=auto`,
the default ([ADR-0019](../adr/0019-auto-backend-best-layer-per-api.md)). Once D3DMetal is imported,
`auto` serves DX12 from it, with no per-game setting.
The GPTK download is a disk image that contains a second one, "Evaluation environment for Windows
games 3.0.dmg". Mount that inner image; `redist/lib` holds D3DMetal.

## Installing (Inno Setup + FreeArc installers)
On stock CrossOver 26.1 the installer froze at 34 MB / 11 files: FreeArc's `unarc.dll` loops forever
when a 2 GB reservation succeeds. Fixed in the runtime by `patches/crossover/0002`
([ADR-0020](../adr/0020-wow64-laa-top-reservation.md)), active on every Decant launch. Verified
2026-11-05: the installer completed in the `games` bottle (5,953 files) and Hades II reached its main
menu there next to Steam. Launch it from a current Decant: an older
bundled CLI doesn't set `DECANT_WOW64_RESERVE_TOP`, and the freeze comes back.

## How to tell it's working
`Hades II.log` shows `GPU[0] detected ... GPU Name: AMD Compatibility Mode` (D3DMetal's stand-in name),
then `Renderer Initialized` and `Renderer Loaded`, and no `Assert`. `pgrep -fl F10` shows nothing.
