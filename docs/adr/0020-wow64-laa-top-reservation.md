# 0020. Reserve 0xFFFD0000 in large-address-aware 32-bit processes on CrossOver Wine

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Utsav, Claude

## Context
An Inno Setup + FreeArc installer froze on crossover-26.1.0. It stuck at about 34 MB / 11 files,
with `setup.tmp` at 100% CPU, and it ignored "Exit Setup". It only finished in the `fg-cxgate` bottle,
whose runtime is staging 11.21 with CrossOver's `wow64cpu.dll` swapped in. That swap fixes a separate
staging crash in the 32→64-bit gate. CrossOver already has the same `wow64cpu.dll`.

Evidence (2026-11-05):
- `winedbg` on the frozen process: the spinning thread is in FreeArc's `unarc.dll` (`+0xaaf4`), inside
  `NtFreeVirtualMemory`.
- Disassembly of `unarc.dll` at `0x6108a904`: the largest-reservable-block search is
  `lo=0, hi=0xFFFFFFFF; do { release; mid=(lo+hi)>>1; reserve(mid) ? lo=mid : hi=mid; } while (hi-lo > 1)`.
  `lo+hi` is 32-bit. If the first `reserve(0x7FFFFFFF)` succeeds, `mid` wraps around and shrinks to 0,
  and `reserve(0)` then fails forever.
- A probe (`tests/fixtures/largestblock.c`; a 32-bit, large-address-aware program) gave the same result
  on every run:
  - crossover-26.1.0 (Wine 11.0): reservation granted at `0x7FFF0000`, largest free block 2048 MB at
    `0x7FFE1000`, and the search hangs.
  - staging 11.21, stock and cxgate: reservation fails (error 8), largest block 1970 MB, and the search
    ends in 32 steps.
- The difference, from mapping 0x70000000-0xFFFFFFFF: upstream Wine 11.21 has a 64 KB committed
  block at `0xFFFD0000`, so the space above 2 GB is just under 2 GB. CrossOver's Wine 11.0 leaves
  `0x7FFE1000-0xFFFEFFFF` free.
- Not the cause: the free-RAM wrap hypothesis. `GlobalMemoryStatusEx` and `AvailablePages` are the same
  on all three runtimes.

## Decision
- **Patch:** `patches/crossover/0002-ntdll-wow64-reserve-top-64k-for-laa.patch`. In
  `virtual_set_large_address_space`, a wow64 process whose image is large-address-aware reserves
  64 KB at `0xFFFD0000` (`MEM_RESERVE`, `PAGE_NOACCESS`) when `DECANT_WOW64_RESERVE_TOP` is set. That
  matches upstream's layout closely enough that no block above 2 GB reaches 2 GB.
- **Opt-in, per ADR-0015:** `bottle_env` exports `DECANT_WOW64_RESERVE_TOP=1` on every launch; other Wine
  builds ignore it. Without it, the patched runtime behaves exactly like stock CrossOver (verified).
- `build-wine.sh` applies the patch to every CrossOver build. The installed crossover-26.1.0 was updated
  by rebuilding only `dlls/ntdll/ntdll.so` from the patched tree.

## Alternatives considered
- **Run such installers on the staging+cxgate runtime:** that's a second runtime and a per-program choice,
  which the user rejected; and staging can't drive D3DMetal or DXMT.
- **A recipe or shim for unarc.dll:** app-specific, and the same DLL ships in many unrelated installers.
  The behaviour gap is in Wine's address-space layout, not in one app.
- **Lower `user_space_wow_limit` to `0xFFFEFFFF`:** the free block would then be `0x7FFF0000-0xFFFEFFFF`,
  exactly 2 GB, and the reservation would still succeed.
- **Port upstream's change wholesale:** the exact upstream commit wasn't identified offline. This patch
  reproduces its observable layout in seven lines, and is easy to drop once CrossOver rebases past it.

## Consequences
- One CrossOver-based runtime now covers what `fg-cxgate` was kept for. Together with ADR-0019, a single
  bottle runs installers, Steam, DX11 and DX12 games.
- 64 KB of a large-address-aware 32-bit process's 4 GB is unavailable, as on upstream Wine.
- Revisit, and drop the patch, when CrossOver's source includes upstream's layout. The live test
  (`tests/live.sh`, "FreeArc's search ends") will keep passing without the patch then.
