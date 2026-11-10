# 0019. One runtime serves every API: `BACKEND=auto` picks the best layer per API at launch

- **Status:** Accepted. Supersedes the "new bottles get DXMT, else DXVK" part of [0011](0011-backend-by-runtime-capability.md); its capability check stays and now also covers D3DMetal.
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
The backend was one fixed choice per bottle, and the runtime was too. One user ended up with three bottles:
- `games`: staging + DXVK, for Steam and DX11.
- `fg-cxgate`: staging, for an installer.
- `fg-d3dm`: CrossOver + D3DMetal, for Hades II, which is DX12 only.

A DX12 game in the Steam bottle needed the whole bottle switched, which then broke the DX11 games.
The user's requirement: one runtime that serves everything on demand, with no per-game choices.

Facts that shape the answer:
- **dxgi.dll is shared** by DX10, DX11 and DX12. One implementation has to own `dxgi`, `d3d10`, `d3d11`
  and `d3d12` together. D3DMetal covers all four; DXMT covers DX10/11 (its d3d11 refuses a non-DXMT dxgi).
- **DX9 and older, DirectDraw and OpenGL** are separate DLLs, served by Wine's own wined3d. Vulkan games
  go to MoltenVK. None of these conflict with the DX10-12 layer.
- **DXVK-macOS ships only `d3d10core`/`d3d11`** (no d3d9), so on a runtime that can present with Metal it
  serves nothing that D3DMetal or DXMT don't. It still matters on runtimes that can't (prebuilt
  staging; ADR-0011).
- **D3DMetal needs the same macdrv exports as DXMT.** On staging-11.21-cxgate it failed with
  `d3d12.dll failed to initialize`; on crossover-26.1.0 Hades II renders.
- **CrossOver's winevulkan must load MoltenVK directly.** Built against the Khronos loader, it never
  enables `VK_KHR_portability_enumeration`, so the loader hid MoltenVK and every DXVK game failed with
  `Required Vulkan extension VK_KHR_surface not supported` (Silksong, 9 Kings). `build-wine.sh` now
  prefers `libMoltenVK.dylib` as `SONAME_LIBVULKAN`.

## Decision
- **New bottles get `BACKEND=auto`**, and `bottle set BACKEND=auto` is allowed. `auto` is resolved from
  what's installed every time `bottle_env` runs, so importing D3DMetal later upgrades every auto bottle
  on its next launch:
  1. On a runtime with the macdrv exports: D3DMetal if imported, otherwise DXMT. Either one owns
     DXGI + DX10/11 (+12 with D3DMetal), and everything else stays on Wine's builtins.
  2. Otherwise: DXVK if installed, otherwise wined3d.
- **DXVK's DLLs are in the prefix exactly while the resolved backend is DXVK.** `dxvk_sync` copies them
  in or restores Wine's, whenever the result changes (a runtime change, or a backend installed or removed).
- The launch log header names the resolved backend (`# backend: d3dmetal`).
- Explicit backends (`dxmt`, `d3dmetal`, `dxvk`, `wined3d`) still work as overrides for debugging.
  `need_backend_ok` refuses DXMT and D3DMetal on runtimes without the exports.
- No per-program or per-recipe runtime or backend: recipes stay for app quirks (args, env, shims).

## Alternatives considered
- **Per-program runtime/backend overrides** (drafted, then dropped): it makes the user pick a setup per
  game, and different runtimes can't share one prefix's wineserver, so Steam and its games couldn't
  run side by side.
- **Pick by the exe's imports** (d3d12 → D3DMetal, d3d11 → DXMT): with dxgi shared, two layers can't
  serve one bottle at the same time, and many DX11 games import d3d12 for optional paths.
- **Keep DXMT as the DX11 layer even when D3DMetal is present:** DX11 and DX12 would then need different
  dxgi DLLs. D3DMetal covers DX11 too, and it's what CrossOver ships.

## Consequences
- One CrossOver-based bottle runs Steam, DX11 and DX12 games, and old DX9 titles together.
- D3DMetal stays bring-your-own (ADR-0004). Without it, DX12 games don't render, and DX10/11 games use DXMT.
- Not covered yet: the Inno Setup + FreeArc installer that freezes on CrossOver 26.1 (investigation brief, finding B).
  It only finished on staging-11.21-cxgate. That's a Wine bug to fix in the runtime, not a backend choice.
- Revisit if a layer starts covering DX9 on Metal (then add it to `auto`), or if D3DMetal regresses DX11 titles.
