---
type: Note
title: "Discovery: agentevent-sessionid"
description: Add a computed var sessionID to AgentEvent (every payload already carries it) and delete the two 12-case re-enumeration switches that exist only to extract it; separately flag the missing mergeGeminiMetadata latent bug
tags: ["discovery"]
timestamp: 2026-07-09T13:00:00Z
# --- octospec extension fields ---
slug: agentevent-sessionid
upstream: arch-quality-audit-r2 (discovery finding #10, cluster C — second half)
source: self
---

# Discovery: agentevent-sessionid

> The **Discover** phase output. Read-only exploration BEFORE the brief. This is
> the SAFE half of cluster-C #10 (the sessionID extraction). The reducer-arm
> collapse and metadata-type unification are deliberately NOT in this slice
> (scout: reducer needs a test net first; metadata types diverge too far; Layer-B
> mergers are defensible mirroring). A separate latent bug (missing
> `mergeGeminiMetadata`) is flagged here for its own future slice — NOT fixed here.

## Relevant files
- `Sources/OpenIslandCore/AgentEvent.swift` — the `AgentEvent` enum (12 cases,
  `:241-253`). Every associated-value payload struct has a `public var sessionID:
  String` (confirmed: 12 structs, all with `sessionID` at lines 4/53/72/88/104/130/
  146/162/178/194/210/226). This is where the new computed property lands.
- `Sources/OpenIslandApp/AppModel.swift:1541-1556` — an inline closure
  `eventSessionID: String?` switching all 12 cases just to read `p.sessionID`, then
  `eventSessionID.flatMap { state.session(id: $0) }`.
- `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift:374-401` —
  `private func sessionID(for event: AgentEvent) -> String?`, a 12-case switch
  returning `payload.sessionID`. Called at `:359` and `:367`, both via
  `guard let sessionID = sessionID(for: event) else { return }`.

## Existing behavior
- Both switches are total (all 12 cases) and each arm returns the same thing:
  `payload.sessionID` (a non-optional `String`). They are pure boilerplate — the
  enum already knows its sessionID; callers just can't ask for it directly.
- Both currently type the result as **`String?`** (AppModel's closure returns
  `String?`; the coordinator func returns `String?`), even though every arm yields
  a non-optional `String`. So both call sites treat it as optional
  (`flatMap` / `guard let`) — an optionality that is, in practice, never nil.
- Adding one event case today means editing 6 mirrored sites (5 in AgentEvent's
  Codable machinery + these 2 sessionID switches). This slice removes 2 of them.

## Contracts & blast radius
- **New `var sessionID: String` on `AgentEvent`** (non-optional — every payload has
  it). A single switch inside the enum, colocated with the cases it enumerates, so
  a future added case is a compile error right next to the definition.
- **AppModel**: replace the inline `eventSessionID` closure with `event.sessionID`
  (now non-optional). `let session = state.session(id: event.sessionID)` — drop the
  `flatMap` (session lookup itself still returns optional). Behavior identical:
  same sessionID, same session lookup, same `relay.notifyEvent`.
- **ProcessMonitoringCoordinator**: delete the private `sessionID(for:)`; the two
  callers become `let sessionID = event.sessionID` (no `guard`, since non-optional).
  Behavior identical — the `guard ... else { return }` never returned early in
  practice (no arm produced nil). This IS a subtle semantic tightening: previously
  the early-return was dead (unreachable) code; removing it is behavior-preserving.
- `SessionState.apply` is NOT touched (that's the reducer-arm collapse, excluded).
- `AgentEvent.swift` is gated by `bridge-transport-invariants` (load-bearing) — BUT
  this slice adds only a computed property; it does NOT touch `CodingKeys`,
  `EventType`, `init(from:)`, or `encode(to:)`, so the wire format is untouched.
  Still, the rule injects and the Codable round-trip tests must stay green.

## Risks & unknowns
- **Non-optional vs optional return**: the new property is `String` (not `String?`).
  Call sites relying on optionality (`flatMap`, `guard let`) must be rewritten. The
  guard early-returns were unreachable (every arm non-nil), so removing them is
  safe — but Verify should confirm no OTHER caller depended on a nil sentinel.
- **Are there other 12-case sessionID switches?** grep found only these two
  (AppModel:1543, ProcessMonitoringCoordinator:376). The other full switches
  (AgentEvent.encode:338, SessionState.apply:58, AppModel.applyTrackedEvent:1798)
  do per-case WORK, not just sessionID extraction — leave them.
- **Testability**: add a direct unit test asserting `event.sessionID` equals the
  payload's sessionID for a representative sample of cases (at least one metadata +
  one non-metadata + the actionableStateResolved tail) — a valid failing-first test
  (the property doesn't exist yet).
- **LATENT BUG (flag, do NOT fix here):** `SessionDiscoveryCoordinator.swift:250-253`
  merges Codex/Claude/OpenCode/Cursor metadata on rediscovery but **omits Gemini**
  (no `mergeGeminiMetadata`), so Gemini metadata is dropped across a rediscovery
  merge. This is unrelated to the sessionID extraction and out of scope; it will be
  recorded as its own finding/slice so it isn't lost.
