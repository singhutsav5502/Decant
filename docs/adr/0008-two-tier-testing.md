# 0008. Test in two tiers: fake-Wine suite + live-Wine suite

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Most of Decant's logic is file and environment orchestration, which a fake `wine` can observe. But the
shim's behaviour (command-line rewriting, environment, exit codes) only means something inside real Wine.
Real Wine needs Rosetta, a downloaded runtime and about 50 s to create a prefix.

## Decision
- `tests/run.sh`: a throwaway `DECANT_HOME` with a fake runtime whose `wine` records argv and
  env. It covers bottles, backends, the APFS overlay, the DXVK swap/restore, and the whole recipe engine
  (matching, args/env/DLL/REG, 32/64-bit shim choice, idempotency, app-update adoption,
  disable/revert, user override). It runs in seconds and needs nothing installed.
- `tests/live.sh`: clones the user's real runtime into a throwaway home, builds
  `tests/fixtures/echoargs.c`, and checks shim injection, skip tokens, `env=`, exit-code propagation and
  `DECANT_SHIM_DISABLE` inside real Wine. It skips itself when there's no runtime or no mingw.

## Consequences
- Every invariant in ARCHITECTURE.md has a test. New mechanisms must add tests to the right tier.
- The tests never touch the user's real bottles.
- App-level behaviour (does Steam render?) still needs a manual check, recorded in the recipe's case
  notes with a `VERIFIED=` line.
