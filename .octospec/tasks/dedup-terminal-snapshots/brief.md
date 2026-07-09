---
type: Task
title: "Task: dedup-terminal-snapshots"
description: Extract the byte-identical GhosttyTerminalSnapshot/TerminalTabSnapshot structs into shared model types, keeping typealias shims for external references
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T05:03:47Z
# --- octospec extension fields ---
slug: dedup-terminal-snapshots
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T05:06:48Z
---

# Task: dedup-terminal-snapshots

> Tenth slice of the `arch-quality-audit-r2` discovery — the second cut of finding
> #9 **cluster A**, building on the `TerminalProbeSupport` shared home established
> by `dedup-terminal-normalize`. Independent branch off `origin/main`.

## Goal

`GhosttyTerminalSnapshot` and `TerminalTabSnapshot` are **byte-identical** nested
structs defined in BOTH `TerminalJumpTargetResolver.swift:14-23` and
`TerminalSessionAttachmentProbe.swift:18-27`:
```swift
struct GhosttyTerminalSnapshot: Sendable { var sessionID: String; var workingDirectory: String; var title: String }
struct TerminalTabSnapshot: Sendable { var tty: String; var customTitle: String }
```
Both are pure data (no methods, no extensions). Move them to **shared top-level
types** in `Sources/OpenIslandApp/TerminalProbeSupport.swift` (the shared-home file
from the prior slice), delete the four nested definitions, and preserve every
existing reference — including the **external qualified** names
`TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot` /
`.TerminalTabSnapshot` — via `typealias` shims inside the Probe.

Behavior is unchanged (the structs are identical pure data); this is a pure
de-duplication that shrinks cluster A further.

## Background

- **Reference map (why the shims are needed):**
  - Inside `TerminalSessionAttachmentProbe` (17 Ghostty + 12 Tab refs) and
    `TerminalJumpTargetResolver` (7 + 7): bare names — resolve to the top-level
    type automatically once the nested defs are removed.
  - **External qualified refs (must keep resolving → `typealias` shims on the
    Probe):** `ProcessMonitoringCoordinator.swift:154-155,232-233`
    (`TerminalSessionAttachmentProbe.SnapshotAvailability<TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot>`
    etc.), `TerminalSessionAttachmentProbeTests.swift` (~22 refs, e.g.
    `[TerminalSessionAttachmentProbe.TerminalTabSnapshot]`), and
    `AppModelSessionListTests.swift:1403`.
  - **Resolver structs are internal-only** — verified NO external qualified
    `TerminalJumpTargetResolver.GhosttyTerminalSnapshot`/`.TerminalTabSnapshot`
    references exist anywhere, so the Resolver needs no shim (bare internal refs
    just resolve to the top-level type).
- `SnapshotAvailability<Snapshot: Sendable>` (Probe `:35`) is generic over these
  snapshot types; the shims keep its public generic signatures
  (`SnapshotAvailability<GhosttyTerminalSnapshot>` etc.) working unchanged.
- Mirrors the merged cluster-A/cluster-C dedups: shared type, behavior-neutral,
  proven by the callers' existing tests. The heavily-tested Probe suite
  (`TerminalSessionAttachmentProbeTests`, ~40 cases via `sessionResolutionReport`)
  is the neutrality proof.
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump)
  — behavior must be preserved.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 4 nested struct definitions** (`TerminalJumpTargetResolver.swift:14-23`,
  `TerminalSessionAttachmentProbe.swift:18-27`) — deleted; replaced by 2 shared
  top-level types in `TerminalProbeSupport.swift`. `[terminal] [applescript]`
- **`typealias` shims in `TerminalSessionAttachmentProbe`** — keep
  `TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot` /
  `.TerminalTabSnapshot` resolving for the ~40 external references. `[terminal]`
- **`SnapshotAvailability` + the `ghosttySnapshotAvailability()` /
  `terminalSnapshotAvailability()` API** and `ProcessMonitoringCoordinator`'s use
  of it — signatures/types must be unchanged. `[terminal]`
- **All existing snapshot references** (Sources + Tests) — must compile and behave
  identically. `[terminal]`

## Out of scope
- **The rest of cluster A** — AppleScript source strings, `runAppleScript`,
  `isRunning`, `corrected*JumpTarget` (Ghostty variant differs — Probe Zellij
  guard). Later slices.
- **No injection-seam refactor**; no change to `SnapshotAvailability`'s shape or
  the availability-producing methods' logic.
- No behavior change, no field rename, no public API change beyond relocating the
  two types (with compatibility shims).

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — the two snapshot types are shared top-level types with their exact
  fields.** `GhosttyTerminalSnapshot(sessionID:workingDirectory:title:)` and
  `TerminalTabSnapshot(tty:customTitle:)` exist as top-level `Sendable` structs
  (in `TerminalProbeSupport.swift`) and construct + expose those exact stored
  properties. *(Testable: a unit test constructs each and reads its fields; the
  memberwise init + field names are the contract. Fails first — as top-level types
  they don't exist yet.)*
- **A2 — the external qualified names still resolve (shim compatibility).**
  `TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot` and
  `TerminalSessionAttachmentProbe.TerminalTabSnapshot` still refer to the shared
  types (so `ProcessMonitoringCoordinator` and the existing test suites compile
  unchanged). *(Testable: a test references the qualified names and assigns a
  shared-type value to them / uses them in `SnapshotAvailability`. Fails first if
  the shim is missing.)*
- **A3 — no duplicated struct definition remains.** Neither file defines a nested
  `GhosttyTerminalSnapshot`/`TerminalTabSnapshot` struct; the definitions live in
  exactly one place. *(Verifiable by grep — only the shared defs + typealiases
  remain.)*
- **A4 — behavior neutral + gate green.** The existing
  `TerminalSessionAttachmentProbeTests` and `AppModelSessionListTests` pass
  unchanged; `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself; the
  existing suites are the behavior-neutral proof.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
