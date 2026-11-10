# 0022. Publish Decant under MIT, Wine patches under LGPL-2.1-or-later, with CI on macOS

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Utsav, Claude

## Context
Decant is being published as an open-source project. Until now the repository had no licence, so nobody
else could legally use, change or redistribute it. Most of Decant (the bash CLI, the SwiftUI app, the
shims, recipes and docs) is original work that only runs Wine as a separate program and doesn't link it.
`patches/crossover/` is different: those files change Wine's own source (ADR-0015), and Wine is
LGPL-2.1-or-later. A public project also needs its rules checked on every contribution, not only on the
maintainer's machine (ADR-0008 defines the two test tiers).

## Decision
- Decant is MIT-licensed (`LICENSE`).
- Everything under `patches/` is LGPL-2.1-or-later, the licence of the code it changes
  (`patches/LICENSE`). The root `LICENSE` names this exception.
- Recipes and docs are for software the user is licensed to run.

## Alternatives considered
- **GPL or LGPL for all of Decant:** stronger copyleft, but nothing in Decant links Wine, so it isn't
  required, and it makes reusing the CLI or recipes in other launchers harder.
- **Apache-2.0:** adds a patent grant, but it's longer and adds little for a project this size.

## Consequences
Anyone can use and fork Decant. Changes to `patches/` must stay LGPL-compatible. CI catches bash 3.2,
syntax and fast-test failures before merge, but the live shim behaviour is still only tested locally.
