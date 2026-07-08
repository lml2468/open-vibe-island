---
type: Task
title: "Task: dedup-registries"
description: Extract a generic SessionRegistry for the 4 near-identical per-agent session persistence layers, keeping public APIs stable
tags: ["refactor", "dedup", "registry", "persistence", "session-discovery"]
timestamp: 2026-07-08T06:26:28Z
# --- octospec extension fields ---
slug: dedup-registries
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-08T08:40:52Z
---

# Task: dedup-registries

> Sixth slice of the `arch-quality-audit` discovery (finding #6, registry
> dimension). Scoped to the **session-registry persistence duplication** — the
> single cleanest, highest-confidence dedup target. The per-agent *installer*
> duplication (the other half of #6) and the metadata-merge duplication (#11) are
> separate future slices; see Out of scope.

## Goal
Four per-agent session-persistence types have byte-identical `load()`/`save()`/
URL logic, differing only in the record type and the filename:

- `ClaudeSessionRegistry` (`ClaudeSessionRegistry.swift`)
- `CursorSessionRegistry` (`CursorSessionRegistry.swift`)
- `OpenCodeSessionRegistry` (`OpenCodeSessionRegistry.swift`)
- `CodexSessionStore` (`CodexSessionTracking.swift:177`)

Each repeats: `fileExists` guard → `Data(contentsOf:)` → `JSONDecoder` with
`.iso8601` → decode; and `createDirectory` → `JSONEncoder` with `.iso8601` +
`[.prettyPrinted, .sortedKeys]` → `.atomic` write. Extract this into one generic
`SessionRegistry<Record: Codable & Sendable>` (or a shared helper the four types
delegate to) so the persistence logic lives in **one** place. **Public API and
on-disk format must not change** — callers (`SessionDiscoveryCoordinator`) and
existing registry files keep working unchanged.

This removes ~300 LOC of copy-paste and the drift risk the audit flagged (e.g.
`CursorTrackedSessionRecord` has no custom `CodingKeys` while the others do — a
silent inconsistency that a shared layer makes impossible to reintroduce in the
persistence path).

## Background
- All four are `@unchecked Sendable`, hold a `fileURL` + `FileManager`, and expose
  the same `defaultDirectoryURL` (rooted at `CodexSessionStore.defaultDirectoryURL`),
  `defaultFileURL`, `init(fileURL:fileManager:)`, `load() throws -> [Record]`,
  `save(_:) throws`.
- The **record structs stay as-is** — their per-agent `CodingKeys`/`init(from:)`
  are payload concerns, not persistence, and must not be touched.
- Sole consumer: `SessionDiscoveryCoordinator` (`:43-52` instantiates all four;
  `:89-135` and `:497-555` call `load()`/`save()`). The public type names should
  remain usable there (typealias or thin subclass over the generic) to keep that
  file unchanged or nearly so.
- Safety net: `ClaudeSessionRegistryTests`, `CursorSessionRegistryFirstSeenTests`,
  `OpenCodeSessionRegistryTests` exist. `CodexSessionStore` has **no** dedicated
  test — add round-trip coverage for it as part of this slice (it's being touched).
- Verified on current `main` (post #21): the four load/save bodies are identical
  (JSON, `.iso8601`, `.atomic`, prettyPrinted+sortedKeys); all consumed only by
  `SessionDiscoveryCoordinator`.

## Load-bearing list
- **The four persistence types' public surface** — `defaultDirectoryURL`,
  `defaultFileURL`, `init(fileURL:fileManager:)`, `load()`, `save(_:)`. Must stay
  source-compatible for `SessionDiscoveryCoordinator`.
- **On-disk format** — filenames
  (`{codex,claude,opencode,cursor}-session-registry.json` / the Codex store's
  file), JSON encoding (`.iso8601` dates, `.prettyPrinted`, `.sortedKeys`), atomic
  write. A file written by the old code must still load, and vice versa.
- **`CodexSessionStore.defaultDirectoryURL`** — the shared root the other three
  reference; must remain the canonical source so all four keep pointing at the
  same directory.
- **Record structs** (`*TrackedSessionRecord`, `CodexTrackedSessionRecord`) —
  unchanged; the generic is parameterized over them.
- **`SessionDiscoveryCoordinator`** — the consumer; behavior must be identical.
- **Existing registry test suites** — must pass unchanged.

## Out of scope
- The per-agent **installer** dedup (`*HookInstaller` / `*HookInstallationManager`
  — discovery #6 H1–H3). Separate slice; the `ConfigBackup` extraction already
  started that direction.
- The **metadata-merge** duplication (`merge*Metadata` in
  `SessionDiscoveryCoordinator` — discovery #11). Separate slice.
- Any change to record struct fields, their `CodingKeys`, or the session-discovery
  *logic* (reconcile/merge). This is a pure persistence-layer extraction.
- Changing the on-disk filenames or JSON shape (that would break existing installs).
- Folding `CodexSessionStore` out of `CodexSessionTracking.swift` into its own file
  (nice, but not required; keep the move minimal).

## Acceptance
- **A1 — single persistence implementation.** The JSON load/save/atomic-write +
  directory-create logic exists in exactly one place (a generic
  `SessionRegistry<Record>` or shared helper); the four types no longer each
  contain a full copy (grep: only one `.write(to:` + `JSONEncoder` persistence
  body across the registry types).
- **A2 — stable public API.** `SessionDiscoveryCoordinator` compiles unchanged (or
  with only mechanical construction changes); `ClaudeSessionRegistry` /
  `CursorSessionRegistry` / `OpenCodeSessionRegistry` / `CodexSessionStore` still
  expose `defaultFileURL`, `init(fileURL:fileManager:)`, `load()`, `save(_:)`.
- **A3 — format compatibility (round-trip).** A test writes records via the new
  code and reads them back equal; and a fixture file in the **old** on-disk format
  (iso8601 dates, pretty+sorted keys) still decodes correctly. Filenames unchanged.
- **A4 — Codex store covered.** New round-trip test for `CodexSessionStore`
  (previously untested) passes.
- **A5 — no behavior regression.** All existing tests pass, especially
  `ClaudeSessionRegistryTests`, `CursorSessionRegistryFirstSeenTests`,
  `OpenCodeSessionRegistryTests`.
- **A6 — gate green.** `zsh scripts/harness.sh ci` passes (warnings-as-errors +
  SwiftLint strict); no new warnings; net LOC reduced.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
