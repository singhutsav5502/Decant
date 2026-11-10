# Working on Decant

Decant runs Windows apps on Apple Silicon Macs (Rosetta + Wine + DirectX→Metal). Read these before
changing anything structural:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): what exists, on-disk layout, the `decant run` flow, invariants.
- [docs/adr/](docs/adr/README.md): why it's built this way. **Check the relevant ADRs before proposing
  an infrastructure change; don't silently reverse an accepted decision.**
- [docs/fixes/README.md](docs/fixes/README.md): recipe format and the method for diagnosing a broken app.
- [docs/integrations.md](docs/integrations.md): store-integration plugin interface (Steam, and future GOG/Epic).

## Rules
1. **No app-specific logic in `bin/decant`.** Making an app work = a `fixes/<id>.fix` recipe plus
   `docs/fixes/<id>.md` case notes. If the recipe keys can't express it, propose a new general mechanism
   (an ADR + tests + docs), not a special case.
2. **Infrastructure decisions get an ADR** in the same change (`docs/adr/`, copy `0000-template.md`, add it
   to the index). Accepted ADRs are only ever superseded, never edited.
3. **Every change gets a `CHANGELOG.md` entry** under `[Unreleased]`. Update `docs/ARCHITECTURE.md` when
   the structure, layout or invariants change.
4. **Stores are plugins** (`integrations/<id>`, read-only). Never parse a store's files in `bin/decant`.
5. **bash 3.2 only** in `bin/decant` and scripts (no associative arrays, `mapfile`, `${x,,}`), and pipefail-safe: never pipe into `head`,
   `grep -q` or an early-exiting `awk`.
6. **Tests:** run `bash tests/run.sh` before finishing. Run `bash tests/live.sh` when touching the shim, `run_wine`,
   `bottle_env` or `fix_apply`. New mechanisms need new tests.
7. **Shim changes:** edit `shim/decant-shim.c`, rebuild the shims with mingw-w64, commit the rebuilt `share/*.exe`.
8. **Never touch the user's real bottles in tests.** Use `DECANT_HOME=$(mktemp -d)`. The real home is
   `~/Library/Application Support/Decant`.
9. **Verify app fixes on screen.** Healthy logs aren't proof; the Steam fix looked fine in the logs while
   the windows were black. Confirm with the user or a screenshot, then update `VERIFIED=`.
10. Decant never downloads Apple's D3DMetal (licence). The user imports it from their own GPTK.
11. **Never run Wine as root or suggest `sudo wine`** (ADR-0013). Elevation is `run --admin`. The only
    privileged step is `repair`'s user-confirmed `chown`.
