# 0010. Expose store libraries through integration plugins

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav, Claude

## Context
The app needs one library showing Steam games, games the user added by hand (any `.exe`), and later
other stores (GOG Galaxy, Epic, EA app). Each store keeps its own install records (Steam:
`steamapps/appmanifest_*.acf` and `libraryfolders.vdf`) and has its own launch protocol (Steam:
`steam.exe -applaunch <appid>`). ADR-0005 keeps app knowledge out of the core, and a store is app
knowledge.

## Decision
Store integrations are executables in `integrations/<id>` with a fixed interface:

| Call | Output |
|---|---|
| `<id> title` | display name |
| `<id> detect <prefix>` | Windows path of the store's launcher exe; exit 1 if not installed |
| `<id> games <prefix>` | TSV rows: `id name folder image target args match` |

The core (`decant library`, `play`, `stop`, `integration list`) merges every integration's rows with
the user's `programs.tsv` into entries keyed `<source>:<id>` (`steam:2784470`, `manual:My Game`). It
launches entries with the existing `cmd_run`, so fix recipes still apply, and detects running games by
matching `match` against one lower-cased `ps` snapshot. Programs whose exe is an integration's launcher
are hidden from the game list; the UI shows them as "Open <Store>" instead.

## Alternatives considered
- **Steam code in `bin/decant`:** fastest to write, but violates ADR-0005, and every store would add more.
- **Recipes as integrations:** recipes are flat KEY=VALUE files and can't express "parse these manifests".
- **Talking to Steam over its local API or URL handlers:** undocumented and needs Steam running even to list games.

## Consequences
- Adding a store is one script plus tests; the core and app don't change.
- Integrations are code, so they're reviewed like code. Keep them read-only: they report, and the core acts.
- Stores manage their own installs and uninstalls. Decant only removes `manual:` entries.
- `match` is a heuristic (a substring of the game's Windows command line). Two games sharing a folder
  name would both show as running.
