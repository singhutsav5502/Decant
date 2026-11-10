# 0005. Express app-specific workarounds as declarative fix recipes

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Making Steam work needed a chain of Steam-specific workarounds (see [docs/fixes/steam.md](../fixes/steam.md)).
The first version hard-coded them in `bin/decant` (`steam_wrap`, a Steam-only wrapper exe, flags baked
into `install-steam`). Every new app would add more special cases to the core script, and the reasoning
would get lost in code.

## Decision
App-specific knowledge lives in **recipes**, `fixes/<id>.fix`, using the same `KEY=VALUE` format as
`bottle.conf`. A recipe declares:
- `MATCH`: which executables it applies to (basenames, case-insensitive).
- What it changes: `ARGS`, `ENV`, `DLLOVERRIDES`, `REG` (applied once per recipe version) and `SHIM`
  (ADR-0006). Repeatable keys can appear on several lines.
- Optionally, how to install the app: `INSTALL_URL`, `INSTALL_ARGS`, `PROGRAM`. That makes a recipe a
  complete app profile.
- Provenance: `NOTES`, `SOURCE`, `VERIFIED`.

`decant run` applies matching recipes automatically. Recipes in `$DECANT_HOME/fixes` override built-ins
with the same id. Bottles opt out with `FIXES_DISABLED`; `DECANT_NO_FIXES=1` bypasses all recipes.
`decant fix check` lints recipes against the known key set. The full format is in
[docs/fixes/README.md](../fixes/README.md).

## Alternatives considered
- **Per-app shell hooks** (like Lutris scripts): maximum power, but arbitrary code is hard to review and
  test, and it's a security risk for shared recipes.
- **Keep special cases in the CLI:** doesn't scale, and mixes policy with mechanism.
- **JSON/TOML recipes:** bash 3.2 can't parse them without dependencies (ADR-0001).

## Consequences
- Adding support for an app is a data change plus case notes. The core only changes when a new *kind*
  of mechanism is needed, and that needs a new key, an ADR and tests.
- The mechanisms are deliberately limited. Anything a recipe can't express is a signal to design a
  general mechanism, not to add an escape hatch.
- `bin/decant` must contain no app names (invariant in ARCHITECTURE.md).
