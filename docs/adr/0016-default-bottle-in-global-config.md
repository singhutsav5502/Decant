# 0016. Keep one default bottle, recorded in a Decant-wide `decant.conf`

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
By 0.6.0 there were three bottles (`test`, `test-dxmt`, and later `games`), each on a different
runtime/backend. Add Game, Install Steam and Open Steam each picked a bottle on their own (the first in
the list, or whatever was selected), so new installs landed in experimental bottles and the user asked
"which bottle should I use?". Settings so far were all per bottle (`bottle.conf`); nothing could hold a
choice that spans bottles.

## Decision
- A Decant-wide settings file, `$DECANT_HOME/decant.conf` (same KEY=VALUE format and `conf_get`/`conf_set`
  helpers as `bottle.conf`). Its first key is `DEFAULT_BOTTLE`.
- `default_bottle` resolves to `DEFAULT_BOTTLE` if that bottle still exists, else the only bottle if there
  is exactly one, else nothing (callers then ask). Deleting the default bottle clears the key.
- CLI: `decant bottle default [name]`, `bottle create --default`, a marker in `bottle list`, a line in
  `doctor`. App: ★ in the sidebar, "Make Default Bottle", and every "where should this go?" action
  (Add Game, Install Steam, Open Steam) targets the default.
- The recommended default is a fresh bottle on the newest DXMT-capable runtime with the automatic backend
  (ADR-0011): on this machine `games` (crossover-26.1.0 + dxmt).

## Alternatives considered
- **Remember the last-used bottle:** silently changes where installs go after any experiment.
- **One bottle only, no choice:** bottles are how we isolate experiments and incompatible apps.
- **Store the default in the app's UserDefaults:** the CLI would disagree with the app (ADR-0001).

## Consequences
- New installs have one predictable home; experimental bottles can stay without getting in the way.
- `decant.conf` is the place for future Decant-wide settings, and is now part of the on-disk layout.
- Tests that create bottles must run in a temporary `DECANT_HOME` so they never change the real default.
