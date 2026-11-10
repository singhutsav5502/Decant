# 0004. Default to DXMT; D3DMetal is bring-your-own; DXVK covers DX9

- **Status:** Accepted; default-backend choice superseded by [0011](0011-backend-by-runtime-capability.md)
- **Date:** 2026-11-03
- **Deciders:** Utsav, Claude

## Context
Most PC games target DirectX 11 or 12, and Metal is the only modern GPU API on macOS. The options are:
- **DXMT:** open source, DX10/11 → Metal directly.
- **D3DMetal:** Apple's closed DX11/12 layer from the Game Porting Toolkit, with a licence that bars
  redistribution.
- **DXVK + MoltenVK:** DX9-11 → Vulkan → Metal. MoltenVK lacks geometry shaders and transform feedback.
- **wined3d:** Wine's own path, on deprecated OpenGL.

## Decision
New bottles default to **DXMT**. **D3DMetal** is installed only from the user's own GPTK copy
(`decant backend install d3dmetal <path>`); Decant never downloads it. **DXVK** is offered for DX9 titles.
Each backend's tuning lives in `bottle_env`:
- DXMT: a per-bottle `DXMT_SHADER_CACHE_PATH`, and `METALFX` →
  `DXMT_METALFX_SPATIAL_SWAPCHAIN` + `DXMT_ENABLE_NVEXT`. These names come from DXMT v0.80's binaries.
- DXVK: `DXVK_ASYNC`, a state cache, and the MoltenVK flags. The DLL overrides are derived from the DLLs
  the DXVK build actually ships; DXVK-macOS has no `dxgi`.

## Alternatives considered
- **D3DMetal as the default:** the best DX12 support, but its licence rules out bundling it.
- **DXVK as the default:** extra translation hop, and missing Vulkan features on MoltenVK.

## Consequences
- DX12-only games need the user to supply GPTK.
- Backend env names are verified against real binaries. Re-check them when bumping backend versions.
