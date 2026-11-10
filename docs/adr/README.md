# Architecture Decision Records

An ADR captures one significant decision: the context, what was decided, and what was given up.
ADRs are how Decant keeps **decision continuity**. Anyone, human or agent, changing infrastructure
reads the relevant ADRs first, and records new decisions here instead of only in commit messages.

## Rules

- **When to write one:** any change to architecture, on-disk layout, file formats, external
  dependencies, the CLI/app contract, the build or release process, or a new kind of workaround
  mechanism. App-specific fixes don't need an ADR; they get a case-notes page in `docs/fixes/`.
- **Numbering:** copy [0000-template.md](0000-template.md) to the next free number, `NNNN-kebab-title.md`.
- **Immutable once accepted:** don't rewrite history. To change course, write a new ADR that
  *supersedes* the old one, and only update the old one's `Status:` line to point at it.
- **Same change:** the ADR lands in the same commit/PR as the change it describes, together with an
  entry in [CHANGELOG.md](../../CHANGELOG.md), and updates to [ARCHITECTURE.md](../ARCHITECTURE.md) if
  the structure changed.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-bash-cli-single-source-of-truth.md) | Bash CLI is the single source of truth; the app is a thin shell | Accepted |
| [0002](0002-prebuilt-wine-runtimes.md) | Prebuilt Gcenx Wine by default; self-built Wine is optional | Accepted |
| [0003](0003-apfs-clones-for-builtin-backends.md) | Builtin-DLL backends go into APFS clones of the runtime | Accepted |
| [0004](0004-graphics-backend-defaults.md) | DXMT by default; D3DMetal is bring-your-own; DXVK for DX9 | Partly superseded by 0011 |
| [0005](0005-declarative-fix-recipes.md) | App-specific workarounds are declarative fix recipes | Accepted |
| [0006](0006-launch-shim-over-wine-patch.md) | Inject child-process args with a file shim, not a Wine patch | Accepted |
| [0007](0007-commit-prebuilt-shims.md) | Commit prebuilt shim binaries next to their source | Accepted |
| [0008](0008-two-tier-testing.md) | Two-tier tests: fake-Wine suite + live-Wine suite | Accepted |
| [0009](0009-decision-records-and-changelog.md) | Infra changes require an ADR + changelog entry | Accepted |
| [0010](0010-store-integration-plugins.md) | Store libraries come from integration plugins | Accepted |
| [0011](0011-backend-by-runtime-capability.md) | Pick the graphics backend by runtime capability (DXMT needs exported macdrv symbols) | Accepted (defaults: see 0019) |
| [0012](0012-build-crossover-wine-with-prebuilt-x86-libs.md) | Build CrossOver's FOSS Wine for DXMT, linking prebuilt x86_64 libs (no x86 Homebrew) | Accepted (Mono: see 0017) |
| [0013](0013-run-as-administrator-without-sudo.md) | "Run as administrator" = Wine's admin token via `runas`, never macOS sudo | Accepted |
| [0014](0014-installer-logs-and-activity-status.md) | Log every recognisable installer; judge "stuck" from process activity | Accepted |
| [0015](0015-carry-patches-against-crossover-source.md) | Carry small, opt-in patches against CrossOver's source in `patches/` | Accepted |
| [0016](0016-default-bottle-in-global-config.md) | One default bottle, recorded in a Decant-wide `decant.conf` | Accepted |
| [0017](0017-bundle-wine-mono-in-built-runtimes.md) | Bundle the exact Wine Mono version in self-built runtimes | Accepted |
| [0018](0018-controllers-through-wine-winebus.md) | Controllers go through Wine's winebus; Decant only detects and tests | Accepted |
| [0019](0019-auto-backend-best-layer-per-api.md) | One runtime serves every API: `BACKEND=auto` picks the best layer per API at launch | Accepted |
| [0020](0020-wow64-laa-top-reservation.md) | Reserve 0xFFFD0000 in large-address-aware 32-bit processes on CrossOver Wine (FreeArc installers) | Accepted |
| [0022](0022-open-source-licensing-and-ci.md) | Publish Decant under MIT, Wine patches under LGPL-2.1-or-later, with CI on macOS | Accepted |
| [0023](0023-recommended-setup-command.md) | Define the recommended setup once, in `decant setup` | Accepted |
