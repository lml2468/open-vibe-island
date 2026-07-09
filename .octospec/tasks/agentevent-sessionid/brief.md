---
type: Task
title: "Task: agentevent-sessionid"
description: Add a computed var sessionID to AgentEvent and delete the two 12-case re-enumeration switches (AppModel, ProcessMonitoringCoordinator) that exist only to extract it; separately flag the missing mergeGeminiMetadata latent bug
tags: ["dedup", "reducer", "bridge", "correctness"]
timestamp: 2026-07-09T13:05:00Z
# --- octospec extension fields ---
slug: agentevent-sessionid
upstream: arch-quality-audit-r2 (discovery finding #10, cluster C — second half)
source: self
revision: 1
approvals: []
---

# Task: agentevent-sessionid

> The SAFE half of cluster-C #10. Independent branch off `origin/main`. See
> `.octospec/tasks/agentevent-sessionid/discovery.md`. The reducer-arm collapse,
> metadata-type unification, and Layer-B merger dedup are deliberately excluded
> (per the scoping decision); the missing `mergeGeminiMetadata` latent bug is
> flagged for a separate slice, not fixed here.

## Goal

Every `AgentEvent` payload already carries `sessionID: String`, yet two places
re-enumerate all 12 cases solely to extract it:
- `AppModel.swift:1541-1556` — an inline `eventSessionID: String?` closure switch.
- `ProcessMonitoringCoordinator.swift:374-401` — `private func sessionID(for:) ->
  String?`, called at two `guard let` sites.

Add a single computed `var sessionID: String` to `AgentEvent` (non-optional — every
payload has one), colocated with the cases. Replace both re-enumerations with
`event.sessionID`. This removes 2 of the 6 mirrored sites that must be edited when an
event case is added, and makes the enum self-describing.

## Deliberately NOT in scope

- **Collapsing the 5 `SessionState.apply` metadata arms** — touches the load-bearing
  reducer and 4 of 5 arms lack direct reducer tests; that is a separate C+A slice.
- **Unifying the 5 metadata types / the `AgentEvent` Codable mirroring** — fields
  diverge too far (Claude/Cursor); the Codable machinery is wire-format-risky and
  low-leverage. Not touched.
- **Layer-B BridgeServer mergers** — encode real per-agent hook-event semantics;
  defensible mirroring, left alone.
- **The missing `mergeGeminiMetadata`** (`SessionDiscoveryCoordinator.swift:250-253`)
  — a real latent bug (Gemini metadata dropped on rediscovery), but UNRELATED to the
  sessionID extraction. Flagged in the journal as its own finding; NOT fixed here.

## Background

- **Injected rule:** `bridge-transport-invariants` (load-bearing, gates
  `AgentEvent.swift`). This slice adds ONLY a computed property — it does not touch
  `CodingKeys`/`EventType`/`init(from:)`/`encode(to:)`, so the wire format is
  unchanged; the Codable round-trip + forward-compat tests must stay green as proof.
- The two consumer switches currently type the result `String?` even though every
  arm returns a non-optional `String`; the `flatMap`/`guard let` optionality is
  never nil in practice. The new property is non-optional, so the guards (whose
  early-return was unreachable dead code) are removed — a behavior-preserving
  tightening.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`AgentEvent.sessionID`** (new computed property) — must return the exact
  `sessionID` of the wrapped payload for all 12 cases. `[bridge]`
- **`AppModel.swift:1541-1556`** — inline closure replaced by `event.sessionID`;
  session lookup + relay behavior unchanged. `[bridge]`
- **`ProcessMonitoringCoordinator.swift`** — `sessionID(for:)` deleted; the two
  callers use `event.sessionID` directly (no guard). `markSessionAttached` /
  `markSessionProcessAlive` behavior unchanged. `[reducer] [bridge]`
- **The Codable wire format** — must remain byte-identical (untouched). `[bridge] [ipc]`

## Out of scope
- `SessionState.apply` (reducer arms), the metadata types, the Codable mirroring,
  Layer-B mergers, and the Gemini merge bug (all above).
- The other full-enum switches that do per-case WORK (`AgentEvent.encode`,
  `SessionState.apply`, `AppModel.applyTrackedEvent`) — they are not sessionID
  extractors and stay.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `AgentEvent.sessionID` returns the wrapped payload's sessionID.** For a
  representative sample spanning the case families — a non-metadata event
  (e.g. `.sessionStarted`), a metadata event (e.g. `.claudeSessionMetadataUpdated`),
  and the tail (`.actionableStateResolved`) — `event.sessionID` equals the sessionID
  the payload was constructed with. *(Testable: direct unit test. Fails first — the
  property does not exist.)*
- **A2 — the two re-enumerations are gone, behavior preserved.** `AppModel` uses
  `event.sessionID` (no 12-case closure); `ProcessMonitoringCoordinator` has no
  `sessionID(for:)` and its two callers use `event.sessionID`. The existing
  ProcessMonitoringCoordinator / AppModel behavior (attach + mark-alive on an event,
  relay notify) is unchanged, proven by the existing suites passing. *(Testable via
  existing coordinator/reducer suites + A1; the removal itself is grep-verifiable.)*
- **A3 — wire format untouched.** `AgentEvent` Codable round-trip and forward-compat
  decoding tests (`BridgeForwardCompatDecodingTests`) pass unchanged; no change to
  `CodingKeys`/`EventType`/`init(from:)`/`encode`. *(N/A(test): the existing Codable
  suites are the proof; this slice adds no wire-format behavior to test.)*
- **A4 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate is the proof; A1 is
  the new positive test.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
