# Steam (Windows client)

Recipe: [`fixes/steam.fix`](../../fixes/steam.fix)
**Verified:** 2026-11-04 · wine-staging 11.21 (Gcenx) · bottle backend DXVK · macOS 26.6 · Apple M5.
Signed in with a QR code, reached the library, and played 9 Kings, both from Steam and from Decant's Library.

## Symptoms (without the recipe)
1. **First launch:** the 32-bit bootstrapper finishes the first update stage, restarts, then crashes:
   `Unhandled page fault on read access to 00002EC5 at address 7BF41135`.
2. **After relaunching:** the update completes, but both Steam windows are **solid black**.
   `logs/webhelper.txt` shows `GpuProcessHost: The GPU process crashed!` three times within seconds.
3. **Sign-in:** `cef_log.txt` repeats `Login: Failed to poll auth session. Result 2. Transport Error`.

## Cause
- (1) is a bootstrapper crash during the 32→64-bit client handover. It only happens once per bottle:
  **launching Steam again finishes the update.** No recipe needed.
- (2) and (3): Steam's UI is Chromium (CEF), started as `steamwebhelper.exe`. Under Wine 11 on Apple
  Silicon its multi-process GPU/compositor path paints windows black, and its separate network-service
  process breaks winsock-based polling.

## What didn't work
- `steam.exe -cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-d3d11 -cef-disable-sandbox`
  stopped the GPU-process crashes, and the logs looked healthy, **but the windows stayed black**. The
  process tree still showed 5 `steamwebhelper.exe` processes with `--type=` children, which proved the
  flags never reached Chromium's process model. Lesson: verify on screen, not from the logs alone.

## Fix
- `SHIM` on `bin/cef/cef.win*/steamwebhelper.exe` injects `--disable-gpu --single-process` into the
  top-level helper, skipping `--type=` children. Single-process mode fixes rendering *and* login, because
  networking moves back in-process.
- `ARGS=-noverifyfiles` stops Steam's startup integrity check from swapping the shim back out.
  `-cef-disable-gpu` is kept as a belt-and-braces measure.
- Steam updates still overwrite `steamwebhelper.exe`. Decant re-shims on the next launch and adopts the
  new binary as the real one.

## How to tell it's working
```bash
pgrep -fl steamwebhelper
```
You should see exactly one `steamwebhelper.exe` (the shim) and one `steamwebhelper.decant-real.exe` with
`--disable-gpu --single-process`, and **no** processes with `--type=`. Five or six `--type=` children
means the shim isn't in play, and the windows will be black.

## Playing games
Games installed through Steam run as Steam's children in the same bottle, so they use the **bottle's
backend**. On prebuilt Gcenx Wine that must be DXVK: 9 Kings (Unity 6, DX11) exited after 3 s on DXMT,
and runs on DXVK ([ADR-0011](../adr/0011-backend-by-runtime-capability.md)). Launch from Decant's
library (`decant play <bottle> steam:<appid>`) or from Steam itself; both work.

### On DXMT (CrossOver-based runtime)
Verified 2026-11-04: on a copy of the Steam bottle switched to `crossover-26.1.0` + DXMT, 9 Kings renders
and plays through Steam (DXMT reports a D3D 11.1 device, no metal-view errors). With the Metal HUD on,
it held 60 FPS on DXMT and 59–60 FPS on DXVK: both at the display cap, so no difference in this light
game. Steam asked for a fresh sign-in once after the runtime switch; it treats the new Wine as a new machine.

### On BACKEND=auto (one runtime for everything)
Verified 2026-11-05 on screen: the `games` bottle on `crossover-26.1.0` with `BACKEND=auto`, which resolves
to D3DMetal once GPTK is imported ([ADR-0019](../adr/0019-auto-backend-best-layer-per-api.md)). Steam, 9 Kings
(launched with `decant play`) and Hollow Knight Silksong (Unity 6, DX11 on D3DMetal: "Direct3D 11.0 [level
11.1]", "AMD Compatibility Mode") all render and play. Before the `build-wine.sh` Vulkan fix, both games
crashed on this runtime with DXVK: `Required Vulkan extension VK_KHR_surface not supported`.
Start Steam before its games: with Steam stopped, Silksong logs `Steam failed to initialize` and quits
cleanly after its splash screen.

## Dock icons
Wine gives each Windows process that shows a window its own Dock icon, and never removes it while the
process lives. Normally only Steam's UI process (`steamwebhelper.decant-real.exe`) qualifies, so you see
**one** icon (confirmed 2026-11-04). On a launch where Steam updates itself, `steam.exe` shows its update
window too, and you get a second icon for that session. That second icon is not verified as the cause
of the earlier report, but it matches what was observed: two icons on the update runs, one afterwards.

## Trade-offs
Steam's own UI renders on the CPU, so scrolling the store and library is a little slower. Games launched
from Steam are separate processes and use the bottle's backend (DXVK/DXMT/D3DMetal) → Metal.

## Sources
- notpop/steam-on-m1-wine: a CEF wrapper forcing `--disable-gpu --single-process` — https://github.com/notpop/steam-on-m1-wine
- NNikolaG/bridgewine PR #12: the same flags via a kernelbase patch (the alternative rejected in ADR-0006) — https://github.com/NNikolaG/bridgewine/pull/12
