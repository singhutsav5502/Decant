# 0009. Require an ADR and a changelog entry for infrastructure changes

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** Utsav

## Context
Decant was built over several sessions: some human, some AI-assisted. Decisions made in one session,
like why APFS clones or why a shim instead of a Wine patch, were at risk of being undone in a later one
by someone who didn't know the reasoning.

## Decision
- Infrastructure decisions are recorded as ADRs in `docs/adr/`, following the rules in its README.
- Every user-visible or structural change gets an entry under `## [Unreleased]` in `CHANGELOG.md`
  ([Keep a Changelog](https://keepachangelog.com) format). Releases move these entries under a version
  number matching `DECANT_VERSION`.
- `docs/ARCHITECTURE.md` describes the current state and is updated in the same change.
- `CLAUDE.md` at the repo root holds the working rules for AI agents and links here, so every session
  starts from the recorded decisions.
- App-specific fixes are documented in `docs/fixes/<id>.md` (symptoms, evidence, fix, verification), not ADRs.

## Consequences
- A small cost on every infrastructure change, in exchange for decisions that survive across contributors.
- Reviews should reject infrastructure changes that come without their ADR, changelog entry or doc updates.
