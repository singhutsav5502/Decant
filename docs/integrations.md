# Store integrations

An integration lets Decant's library show and launch the games a store installed inside a bottle.
Why plugins: [ADR-0010](adr/0010-store-integration-plugins.md). Built-in: [`integrations/steam`](../integrations/steam).

## Interface

An integration is an executable `integrations/<id>` (lowercase id, also used as the key prefix). It
receives the bottle's **prefix directory** (the `WINEPREFIX`, containing `drive_c` and `dosdevices`).

| Call | Must do |
|---|---|
| `<id> title` | Print the display name (`Steam`). |
| `<id> detect <prefix>` | If the store is installed, print the Windows path of its launcher exe and exit 0; otherwise exit 1. |
| `<id> games <prefix>` | Print one tab-separated row per **installed, playable** game. No header; exit 0 even if there are none. |

`games` columns:

| # | Column | Example (Steam) |
|---|---|---|
| 1 | `id`: stable per store, no tabs or `:` | `2784470` |
| 2 | `name` | `9 Kings` |
| 3 | `folder`: unix path of the install dir (used for "Show in Finder") | `…/drive_c/…/steamapps/common/9 Kings` |
| 4 | `image`: unix path of cover art, portrait preferred, or empty | `…/librarycache/2784470/…/library_capsule.jpg` |
| 5 | `target`: Windows path to launch | `C:\Program Files (x86)\Steam\steam.exe` |
| 6 | `args`: space-separated launch args | `-applaunch 2784470` |
| 7 | `match`: substring of the running game's command line | `\common\9 Kings\` |

## Rules
- **Read-only.** Integrations report; they never launch, install or modify anything. The core launches
  through `decant run`, so fix recipes still apply.
- Plain bash 3.2 or POSIX sh, no dependencies (ADR-0001). Must be fast: the app polls `decant library`
  every 3 seconds while the library is open.
- Hide non-games: runtimes, redistributables, and partially downloaded installs.
- Add tests to `tests/run.sh` using a fake store layout (see the Steam section), plus a
  `docs/integrations.md` row below.

## Built-in integrations

| Id | Reads | Launches |
|---|---|---|
| `steam` | `steamapps/libraryfolders.vdf` and every library's `appmanifest_*.acf` (StateFlags & 4 = installed) | `steam.exe -applaunch <appid>`, which hands off to a running Steam or starts it |
