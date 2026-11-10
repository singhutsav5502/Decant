# 0003. Put builtin-DLL backends into APFS clones of the runtime

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** Utsav, Claude

## Context
DXMT and D3DMetal ship *builtin* Wine DLLs (`x86_64-windows/*.dll`) plus Unix-side libraries
(`x86_64-unix/winemetal.so`, `D3DMetal.framework`). These must sit inside the runtime's `lib/wine`, and
they replace Wine's own `d3d11`/`dxgi`. Different bottles on the same runtime need different backends.

## Decision
Never modify `runtimes/<name>`. A bottle with backend `dxmt` or `d3dmetal` runs on
`runtimes/<name>+<backend>`, created with `cp -c` (an APFS clone: instant, and it shares blocks until
written), then overlaid with the backend's files. A `.decant-overlay` stamp records the backend version,
so the clone is rebuilt when the backend changes.

Native-DLL backends (DXVK) are copied into the bottle's `system32`/`syswow64` instead. When a bottle leaves
DXVK, Wine's own DLLs are copied back.

## Alternatives considered
- **Overlay onto the base runtime:** breaks every other bottle on that runtime.
- **Full copies:** about 1 GB of disk per runtime×backend.
- **WINEDLLPATH tricks:** builtin Unix libraries are resolved relative to Wine's own lib dir, so it's unreliable.

## Consequences
- Switching backends is cheap and leaves no residue.
- APFS is required (the default on every supported Mac). `cp -R` is used as a fallback.
- Tests assert the base runtime is untouched (ADR-0008).
