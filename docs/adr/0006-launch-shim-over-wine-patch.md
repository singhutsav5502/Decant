# 0006. Inject child-process args with a file shim, not a Wine patch

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Some fixes need flags on a process that the app starts itself, where Decant has no hook. Steam starts
`steamwebhelper.exe` (Chromium), which needs `--disable-gpu --single-process` under Wine 11 on Apple
Silicon. Steam's own `-cef-*` flags didn't reach it: confirmed by the process tree (5 helpers with
`--type=` children) and by the windows staying black.

## Decision
A generic shim, `shim/decant-shim.c`, built for x64 and x86. The recipe's `SHIM=<glob>|<inject>|<skip>`
tells Decant which file to replace. The real binary moves to `<name>.decant-real.exe`, the shim takes its
name, and a `<name>.decant-shim` sidecar holds `inject=`/`skip=`/`env=` lines. The shim appends the
injected args (unless a skip substring is present), starts the real binary, waits, and returns its exit
code. Decant re-checks shims on every launch, so app self-updates that overwrite a shim are absorbed
(the new file becomes the real binary). The shim contains no app-specific logic.

## Alternatives considered
- **Patch Wine's `CreateProcessInternalW`** (the approach in bridgewine PR #12): no file changes in the
  app, but it needs a custom Wine build, which contradicts ADR-0002's default of prebuilt runtimes, and
  must be re-ported to every Wine version.
- **Image File Execution Options "Debugger" redirect:** no binary needed, but Wine's support is
  uncertain, it needs a `cmd` trampoline with fragile quoting, and it may flash a console window.
- **Per-app wrapper executables:** what v0.1 did for Steam. Every app would need a recompile.

## Consequences
- Works on stock runtimes and needs only one prebuilt binary per architecture (ADR-0007).
- It modifies app files, so apps with strict self-verification need help. Steam uses `-noverifyfiles`;
  others may need a similar flag in their recipe.
- The live test suite runs the shim inside real Wine to guard its behaviour (ADR-0008).
- Revisit if Decant moves to self-built Wine by default. A kernelbase hook could then replace file
  shimming, keeping the same recipe syntax.
