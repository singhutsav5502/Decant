# 0011. Choose the graphics backend by what the runtime can actually drive

- **Status:** Accepted. Supersedes the "default to DXMT" part of [0004](0004-graphics-backend-defaults.md).
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
The first Steam game tried (9 Kings, Unity 6, DX11) exited after 3 seconds on a DXMT bottle. Unity's
`Player.log` showed the D3D11 device being created, and Wine logged:

> `Failed to create metal view, it seems like your Wine has no exported symbols needed by DXMT.`

DXMT's `winemetal.so` calls `macdrv_view_create_metal_view` and related functions in Wine's
`winemac.so`. The prebuilt Gcenx runtime (ADR-0002) builds with hidden visibility and exports **none**
of them, so DXMT can create devices but never present a frame, for any game. On the DXVK backend
(MoltenVK), the same game ran: a 1710×1107 window with the D3D11 device on an Apple M5.

## Decision
- `runtime_supports_dxmt` checks whether `lib/wine/x86_64-unix/winemac.so` contains
  `macdrv_view_create_metal_view` (a plain string search, so no Xcode tools are needed).
- New bottles get `default_backend`: DXMT if it's installed *and* the runtime supports it, otherwise
  DXVK if installed, otherwise wined3d. The app's "Automatic" choice means exactly this.
- Choosing DXMT on an incapable runtime (`bottle create --backend dxmt`, `bottle set BACKEND=dxmt`) is
  refused, with the reason and the alternatives. Existing DXMT bottles on such runtimes log a warning at
  every launch.
- `runtime list` reports capability in a third column (`yes`/`no`), and `doctor` shows it per runtime.
- `scripts/build-wine.sh` now builds with `-fvisibility=default` and reports whether the result is DXMT-capable.

## Alternatives considered
- **Silently fall back to DXVK at launch:** DXVK's DLLs must already be in the prefix, and silent
  substitution hides why performance or behaviour changed.
- **Make self-built Wine the default:** 20-40 minutes and an x86_64 Homebrew. Worth offering, but not as
  the first-run path.
- **Keep DXMT as the default and document the caveat:** every game would fail exactly as 9 Kings did.

## Consequences
- With prebuilt runtimes, games run on DXVK: DX9-11, one extra translation hop, and MoltenVK's feature gaps.
  DX12-only games need D3DMetal (bring-your-own) or a DXMT-capable Wine plus DXMT for DX11.
- A DXMT-capable runtime (self-built, or a future Gcenx build exporting the symbols) automatically gets
  DXMT for new bottles.
- Revisit when Gcenx builds export the macdrv symbols, or DXMT stops needing them.
