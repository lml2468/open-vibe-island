---
type: Task
title: "Task: reducer-metadata-collapse"
description: Collapse the 5 identical SessionState.apply metadata arms into one closure-parameterized helper (guard + mutate + timestamp + upsert), preserving exact behavior; regression net provided by #48
tags: ["dedup", "reducer", "session-state", "correctness"]
timestamp: 2026-07-10T02:40:00Z
# --- octospec extension fields ---
slug: reducer-metadata-collapse
upstream: arch-quality-audit-r2 (discovery finding #10, cluster C — reducer arm collapse, slice A)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-10T02:31:47Z
---

# Task: reducer-metadata-collapse

> Slice A of the reducer-arm C+A (slice C = `reducer-metadata-arm-tests`, merged
> #48). Collapses the 5 identical `SessionState.apply` metadata arms into one
> helper. Completes cluster-C #10. Independent branch off `origin/main`. See
> `.octospec/tasks/reducer-metadata-collapse/discovery.md`.

## Goal

The 5 metadata arms (`SessionState.swift:189-232`) are identical modulo the payload
field + session keypath. Extract a private helper:
```swift
private mutating func applySessionMetadata(
    sessionID: String,
    timestamp: Date,
    mutate: (inout AgentSession) -> Void
) {
    guard var session = sessionsByID[sessionID] else { return }
    mutate(&session)
    session.updatedAt = timestamp
    upsert(session)
}
```
Each arm becomes one line delegating to it, with the per-agent
`isEmpty ? nil : payload.Xmetadata` assignment kept INSIDE the closure (each metadata
type has its own `isEmpty`, so the safety-critical nil-ing stays per-agent and
locally visible — the `HookGroupSanitizer` closure-seam precedent). Byte-equivalent
behavior: guard → assign → set updatedAt → upsert, in the same order.

## Not a Red→Green slice (why)

This is a **pure behavior-neutral relocation** whose four per-arm invariants (set,
isEmpty→nil, deterministic updatedAt, unknown-id no-op) are ALREADY pinned by
`ReducerMetadataArmTests` (merged #48, the C slice landed precisely for this). There
is no meaningful NEW failing-first test — a fresh test would duplicate the net.
Marked `N/A(test)`: the pre-registered #48 net staying green through the collapse,
plus the byte-behavior review, is the proof (same posture as the earlier verbatim
type relocations).

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionState.apply` 5 metadata arms** — replaced by one-line delegations to the
  new helper; the `isEmpty ? nil` stays in each closure. `[reducer] [session-state]`
- **New `applySessionMetadata(sessionID:timestamp:mutate:)`** — the shared
  guard/mutate/timestamp/upsert skeleton; must reproduce the exact order. `[reducer] [session-state]`
- **The #48 net + full reducer suite** — the behavior-neutral proof. `[reducer]`

## Out of scope
- **Non-metadata arms** — `.activityUpdated`/`.permissionRequested`/`.questionAsked`
  (phase-changing, route through `isTerminalAndMustNotResurrect`),
  `.sessionStarted`/`.sessionCompleted`/`.jumpTargetUpdated`/`.actionableStateResolved`.
  Only the 5 pure metadata arms collapse.
- **Adding the terminal resurrection guard to the metadata path** — metadata arms are
  phase-neutral and today accept metadata for any session; routing them through the
  guard would be a behavior change. Do NOT add it.
- Any change to the metadata types, `upsert`, or the event/wire layer.

## Acceptance
<!-- Behavior-neutral relocation; #48 net is the pre-registered proof. -->
- **A1 — the 5 arms delegate to one helper.** After the change, each of the 5
  metadata `case` arms is a single call to `applySessionMetadata(sessionID:timestamp:mutate:)`
  passing a closure that performs only the `session.Xmetadata = payload.Xmetadata.isEmpty
  ? nil : payload.Xmetadata` assignment; the helper owns the guard, `updatedAt`, and
  `upsert`. *(Verifiable by reading the diff — the four inlined lines per arm become
  one delegation.)*
- **A2 — behavior preserved (the #48 net stays green).** `ReducerMetadataArmTests`
  (all 5 arms × set / isEmpty→nil / updatedAt / unknown-id no-op) passes unchanged,
  as do the end-to-end Cursor metadata tests and the full reducer suite. *(Testable:
  the pre-registered net is the proof.)*
- **A3 — invariants intact.** No wall-clock read introduced (timestamp stays the
  helper param); `upsert` still runs on every applied metadata event; the metadata
  path is NOT routed through `isTerminalAndMustNotResurrect`. *(Verifiable by review
  against `session-state-invariants`.)*
- **A4 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + #48 net are the
  proof; no new failing-first test for a pure relocation already covered by the net.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
