# 0001. Make the bash CLI the single source of truth; the app is a thin shell

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** Utsav, Claude

## Context
Decant has two front ends: a command line and a SwiftUI app. If both implemented bottle logic, they
would drift apart. The logic is mostly process orchestration (environment variables, file copies, running
`wine`), which shell expresses directly. Users shouldn't have to install anything beyond macOS itself.

## Decision
`bin/decant` holds all behavior. It's written for the **stock macOS bash 3.2**: no associative arrays,
`mapfile`, `${var,,}` or other bash 4+ features, and no dependencies outside the base OS. The one
exception is `/usr/bin/python3` for parsing GitHub release JSON during downloads. The SwiftUI app only
reads `bottle.conf` and `programs.tsv` and runs CLI commands; it never writes bottle state itself.
`Decant.app` bundles a copy of the CLI, `share/` and `fixes/` in `Contents/Resources`.

## Alternatives considered
- **Swift core library + CLI wrapper:** typed and testable, but every change needs a compile step, and
  scripting or debugging in the field gets harder.
- **Python:** nicer language, but macOS no longer guarantees a Python, and the stub requires Command Line Tools.

## Consequences
- Everything the app can do is scriptable and testable from the shell (see ADR-0008).
- Formats the CLI and app share (`bottle.conf`, `programs.tsv`, the `fix status` TSV) are a contract.
  Changing them means updating `app/Sources/Decant/Models.swift`/`Store.swift` in the same change.
- Revisit if the CLI grows past what bash handles comfortably (~1500 lines) or needs real data structures.
