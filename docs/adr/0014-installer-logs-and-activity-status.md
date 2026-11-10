# 0014. Log every recognisable installer, and judge "stuck" from process activity

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
"Setup seems stuck" was impossible to answer. Decant's launch log only holds Wine's stderr. Installers
write their own step-by-step log only when asked, and nothing showed whether an installer was working
(e.g. decompressing for many minutes) or waiting on a dialog hidden behind another window. Mapping Windows
processes to bottles is also non-trivial: Wine overwrites each process's argv with the Windows command
line, and macOS `ps -E` doesn't show its environment either, so `WINEPREFIX` isn't visible.

## Decision
- **Installer logs on by default.** `cmd_run` and `run_admin` detect the installer type from the exe
  (`Inno Setup` / `Nullsoft` signatures, or the `.msi` extension). Inno Setup gets
  `/LOG=C:\decant-logs\<ts>-<name>.log`; MSI gets `/l*v` (and `--admin` MSI elevates
  `msiexec.exe /i …`). Nothing is added if the user passed their own `/LOG`/`/l*`. Logs live inside
  `drive_c` (a path without spaces, which some installers mangle), and `logs/installer-latest.log`
  links the newest one. The launch log header records it as `# installer-log:`. NSIS release builds have
  no log switch, so they're left alone.
- **`decant status <bottle> [--tsv]`.** Windows processes are mapped to a bottle by the files they have
  open under its prefix (`lsof -Fn`, matching both logical and physical paths). Wine's own services are
  flagged. The verdict is **busy** if a non-Wine process uses ≥ 5% CPU or the installer log changed in
  the last 15 s, **waiting** if programs run but are idle (likely a dialog), and **stopped** otherwise.
- **`decant logs <bottle> [--installer] [--follow]`** and **`decant diagnostics <bottle>`**, which zips
  the summary (status, runtimes, backends, fixes), `bottle.conf`, `programs.tsv`, the last 5 launch logs
  and the last 3 installer logs to the Desktop.
- **App:** an Activity panel (polls `status --tsv` every 2 s) in bottle settings and in Add Game's
  installer step, with Open Launch/Installer Log, Show Logs in Finder, and Export Diagnostics.

## Alternatives considered
- **`WINEDEBUG` tracing by default:** huge logs, slows Wine, and it's unreadable for "is it stuck?".
  It stays opt-in (`EXTRA_ENV=WINEDEBUG=…`).
- **Map processes via `wineserver` sockets:** client sockets have no path in `lsof`. Open prefix files do.
- **Window detection to spot dialogs:** needs Screen Recording/Accessibility permission. CPU plus log
  activity is a good enough proxy, and the message tells the user what to look for.

## Consequences
- Every Inno/MSI install leaves a log, including ones that fail, which is what bug reports need.
- `status` costs one `ps` plus one `lsof` per Windows process (about 0.3 s for a dozen), cheap enough for
  2-second polling while the panel is visible.
- Diagnostics include file paths containing the user's name; the CLI says so when it writes the zip.
