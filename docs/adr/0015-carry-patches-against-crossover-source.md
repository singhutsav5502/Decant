# 0015. Carry small patches against CrossOver's source, in `patches/<mode>/`

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
A fresh bottle on the self-built CrossOver runtime (ADR-0012) got a profile folder
`C:\users\crossover`, while Wine's core set `%USERPROFILE%` to `C:\users\Utsav`. CrossOver forces the
name "crossover" in two places, both marked *CrossOver Hack 12735*:
- `advapi32` `GetUserName`, which has an opt-out, `CX_REPORT_REAL_USERNAME` (Decant sets it on every
  launch since ADR-0012);
- `shell32` `shellpath.c`, which expands `%USERPROFILE%` for known folders (AppData, Documents, Saved
  Games) and has **no** opt-out.

The result was two profiles in one bottle: saves and logins written through known folders went to
`crossover`, and those using `%USERPROFILE%` went to the real name. Bottles also weren't portable
between runtimes, so Steam's saved sign-in in `users\Utsav` was invisible on CrossOver Wine. CrossOver
itself avoids this by running everything as "crossover". Decant runs Wine directly, so that consistency
is gone.

## Decision
Decant keeps unified-diff patches against a source tree in `patches/<mode>/NNNN-<what>.patch`.
`scripts/build-wine.sh` applies them in order after fetching the source. It's idempotent (skips a patch
that's already applied), and stops with a clear error if a patch no longer applies to the requested version.

First patch, `patches/crossover/0001-shell32-honour-CX_REPORT_REAL_USERNAME.patch`: when
`CX_REPORT_REAL_USERNAME` is set, shell32 uses `WINEUSERNAME` (Wine's real user name) instead of the
hard-coded "crossover". That's the same rule as advapi32, so one variable gives one consistent profile.

Patches must stay **small, explained in a comment at the change, and opt-in** (behaviour without
Decant's environment is unchanged), so they're easy to re-port when CrossOver's source moves.

## Alternatives considered
- **Run as "crossover" everywhere (`USER=crossover`):** consistent, but bottles wouldn't be portable to
  the prebuilt runtime (which uses the Mac user name), and existing bottles' data would be stranded.
- **Symlink `users\crossover` → `users\<name>`:** hides the problem until an app compares paths or an
  installer recreates the folder.
- **Patch the binary:** fragile, and invisible in review.

## Consequences
- The verified default bottle (`games`, created 2026-11-04) has a single profile, `C:\users\Utsav`. Its
  known folders, `%USERPROFILE%` and Steam's carried-over sign-in all agree.
- Every CrossOver version bump must re-check `patches/crossover/`. A failing patch stops the build
  rather than producing a subtly broken runtime.
- The runtime built before this patch was fixed in place by replacing `shell32.dll`. Fresh builds get it
  from the patch.
