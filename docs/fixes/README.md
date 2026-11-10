# Compatibility fix recipes

A recipe teaches Decant how to make one app work under Wine, as data rather than code
(why: [ADR-0005](../adr/0005-declarative-fix-recipes.md)). Built-in recipes live in `fixes/<id>.fix`;
your own go in `~/Library/Application Support/Decant/fixes/<id>.fix` and replace a built-in recipe
with the same id.

## Format

Plain `KEY=VALUE` lines (the `bottle.conf` format). `#` starts a comment. Keys marked *repeatable* may
appear on several lines. The id is the file name: lowercase `a-z0-9-`.

| Key | Required | Meaning |
|---|---|---|
| `TITLE` | yes | One line: app and the problem fixed. Shown in `fix list` and in the app. |
| `MATCH` | yes | Space-separated exe basenames that trigger the recipe, case-insensitive (`steam.exe`). |
| `ARGS` | | Args added to the launch, before user args. Args already present aren't repeated. |
| `ENV` | repeatable | `KEY=VALUE` exported for the launch. Values may contain spaces. |
| `DLLOVERRIDES` | | Appended to `WINEDLLOVERRIDES`, e.g. `xinput1_3=n,b;d3dcompiler_47=n`. |
| `REG` | repeatable | `key\|value\|type\|data`, applied with `wine reg add`. Runs once, and again whenever the REG lines change. |
| `SHIM` | repeatable | `glob\|inject args\|skip substrings`. The glob is relative to the matched exe's folder. Each matching file gets the launch shim ([ADR-0006](../adr/0006-launch-shim-over-wine-patch.md)). |
| `INSTALL_URL` | | Installer to download for `decant install <bottle> <id>`. |
| `INSTALL_ARGS` | | Args for the installer, e.g. `/S` for a silent NSIS install. |
| `PROGRAM` | | `label\|windows path`: saved as a launch target after installing. |
| `NOTES` | | Path to the case-notes page, `docs/fixes/<id>.md`. |
| `SOURCE` | | Where the workaround came from (issue, repo, forum). |
| `VERIFIED` | | `date runtime backend macOS hardware` of the last manual check. |

Run `decant fix check` after editing. It rejects unknown keys and malformed `SHIM`/`REG`/`ENV` lines.

### How SHIM works
For `SHIM=bin/helper.exe|--safe|--type=`, when the matching app launches, Decant:
1. Moves `bin/helper.exe` → `bin/helper.decant-real.exe`, and puts `decant-shim` (32- or 64-bit, matched to
   the original's PE header) in its place. This is skipped if the file is already our shim.
2. Writes `bin/helper.decant-shim` with `inject=--safe` and `skip=--type=`.

When the app later starts `helper.exe`, the shim runs `helper.decant-real.exe --safe <original args>`,
unless the original command line contains a `skip` substring, in which case it passes the args through
unchanged. If the app updates itself and overwrites the shim, the next launch adopts the new file as the
real binary. `decant fix disable <bottle> <id>` restores every original file.

Debugging switches: `DECANT_SHIM_DISABLE=1` (the shim passes through), `DECANT_NO_FIXES=1` (no recipes applied).

## Diagnosing a broken app: the method

This is how the Steam fix was found ([steam.md](steam.md)). It applies to any app.

1. **Reproduce in a clean bottle**, and check the plumbing first: `decant doctor`, then
   `decant run <b> cmd /c ver` and `decant winecfg <b>`. If those fail, it's a Wine or runtime problem,
   not something a recipe can fix.
2. **Read the launch log**, `decant logs <b>`. The header shows the exact env and command line. Look for
   `Unhandled page fault`, `err:` lines, and missing-DLL messages.
3. **Turn on targeted Wine tracing** for one launch, with `EXTRA_ENV=WINEDEBUG=+loaddll` (also useful:
   `+seh`, `+module`, `+process`). `+loaddll` shows whether the DLL you expected (builtin vs native,
   backend vs Wine's own) is the one that actually loaded.
4. **Read the app's own logs.** Many apps keep them in their install folder (Steam: `logs/`). Chromium/CEF
   apps write `cef_log.txt` and GPU reports. Search them for `crash`, `GPU process`, `Transport`, `failed`.
5. **Look at the process tree**: `pgrep -fl <name>`. The *shape* of the tree tells you a lot. For example,
   several `--type=` children means Chromium is running multi-process, and so a flag didn't land.
6. **Confirm what's on screen.** A window existing isn't the same as a window rendering. Ask the user or
   take a screenshot. Black or blank windows are their own class of bug, usually GPU or compositing.
7. **Search for prior art** (Whisky, CrossOver, Proton, Heroic, Lutris issues). Prefer fixes several
   sources agree on, and record them in `SOURCE`.
8. **Pick the smallest mechanism that works:** `ARGS` → `ENV` → `DLLOVERRIDES` → `REG` → `SHIM`. Change
   one thing at a time, and check each step against what's on screen, not just the logs.
9. **Write it down:** the recipe, plus `docs/fixes/<id>.md` with the symptoms, evidence, cause, fix, how to
   tell it's working, and the `VERIFIED` details. Add a `CHANGELOG.md` entry.

If you need a mechanism the keys can't express, don't add a workaround to `bin/decant`. Propose a new key
with an ADR, tests and docs ([CLAUDE.md](../../CLAUDE.md)).

## Case notes

| Recipe | Notes |
|---|---|
| `steam` | [steam.md](steam.md): black CEF windows and failed sign-in polling |
| `hades2` | [hades2.md](hades2.md): F10.exe crash reporter instead of the game; DX12 needs D3DMetal (`BACKEND=auto` on a CrossOver runtime) |
