# 0018. Controllers go through Wine's own winebus; Decant only detects and tests

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
Controller games must work without per-game setup. Both runtimes (prebuilt staging and the self-built
CrossOver build) ship `winebus.sys` with SDL2 and macOS IOHID backends, which present pads to Windows
programs as XInput and DirectInput devices (Xbox, PlayStation, Switch Pro and most HID pads). What was
missing was a way for a user to tell whether a problem is "macOS doesn't see the pad", "Wine doesn't see
it" or "the game/Steam Input is ignoring it".

## Decision
- Decant adds **no input layer** of its own (no remapping daemon, no per-game controller config).
- `decant controllers <bottle>` (app: **Game Controllers**) lists the HID joysticks/gamepads macOS sees,
  read from `hidutil list` (usage page 0x1, usages 0x4/0x5/0x8), then opens Wine's Game Controllers panel
  (`control joy.cpl`) in that bottle for a live button test. `DECANT_HIDUTIL` lets tests substitute a fake.
- The output names the one known override: Steam Input can take over pads for Steam games and is turned
  off per game in Steam, not in Decant.

## Alternatives considered
- **Read controllers with IOKit/GameController.framework in the app:** needs Input Monitoring permission,
  and would duplicate logic the CLI should own (ADR-0001).
- **Bundle a remapper (e.g. an XInput wrapper DLL per game):** per-game work, and it hides winebus problems
  instead of exposing them.

## Consequences
- Diagnosis is two steps (macOS list, then joy.cpl) with no permissions prompt.
- Not yet verified with a physical controller on this machine; record the result (pad, transport,
  runtime) in the CHANGELOG when it is.
- If a class of pads needs SDL hints or registry tweaks, that becomes a bottle setting or recipe, decided
  in a new ADR.
