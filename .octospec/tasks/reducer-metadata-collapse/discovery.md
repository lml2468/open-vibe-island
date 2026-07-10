---
type: Note
title: "Discovery: reducer-metadata-collapse"
description: Collapse the 5 identical SessionState.apply metadata arms into one closure-parameterized helper (guard + mutate + timestamp + upsert), preserving exact behavior; net provided by #48
tags: ["discovery"]
timestamp: 2026-07-10T02:35:00Z
# --- octospec extension fields ---
slug: reducer-metadata-collapse
upstream: arch-quality-audit-r2 (discovery finding #10, cluster C — reducer arm collapse, slice A)
source: self
---

# Discovery: reducer-metadata-collapse

> The **Discover** phase output. Read-only. Slice A of the reducer-arm C+A; the
> regression net (`ReducerMetadataArmTests`, 5 arms × 4 properties) landed in #48.
> This collapses the 5 identical metadata arms into one helper. Touches the
> load-bearing reducer.

## Relevant files
- `Sources/OpenIslandCore/SessionState.swift:189-232` — the 5 metadata arms
  (`.sessionMetadataUpdated`/Codex, `.claudeSessionMetadataUpdated`,
  `.geminiSessionMetadataUpdated`, `.openCodeSessionMetadataUpdated`,
  `.cursorSessionMetadataUpdated`). Each is 4 lines, identical modulo the payload
  field + session keypath:
  ```
  guard var session = sessionsByID[payload.sessionID] else { return }
  session.<agent>Metadata = payload.<agent>Metadata.isEmpty ? nil : payload.<agent>Metadata
  session.updatedAt = payload.timestamp
  upsert(session)
  ```
- `SessionState.swift:504` — `private mutating func upsert(_:)`, the shared tail.
- `Tests/OpenIslandCoreTests/ReducerMetadataArmTests.swift` (#48) — the net: for each
  arm, asserts set / isEmpty→nil / updatedAt=timestamp / unknown-id no-op.

## Existing behavior (invariants the collapse must preserve)
Per arm: (1) if the session doesn't exist → no-op (guard returns); (2) assign the
payload's metadata to the agent keypath, nilling it when `isEmpty`; (3) set
`updatedAt = payload.timestamp` (caller-supplied, deterministic); (4) `upsert`.
Metadata arms do NOT change `phase`, so the terminal resurrection guard
(`isTerminalAndMustNotResurrect`) does not apply and must NOT be added — adding it
would be a behavior change (it would start dropping metadata updates for ended
sessions, which today still accept metadata).

## Contracts & blast radius
- **The proposed collapse** — a private helper:
  ```
  private mutating func applySessionMetadata(
      sessionID: String, timestamp: Date, mutate: (inout AgentSession) -> Void
  ) {
      guard var session = sessionsByID[sessionID] else { return }
      mutate(&session)
      session.updatedAt = timestamp
      upsert(session)
  }
  ```
  Each arm becomes one line:
  `case let .sessionMetadataUpdated(payload): applySessionMetadata(sessionID: payload.sessionID, timestamp: payload.timestamp) { $0.codexMetadata = payload.codexMetadata.isEmpty ? nil : payload.codexMetadata }`
  The `isEmpty ? nil :` decision stays INSIDE each arm's closure (per-agent, since
  each metadata type has its own `isEmpty`), so the safety-critical nil-ing is
  locally visible — mirrors the `HookGroupSanitizer` closure-seam precedent.
- `session-state-invariants` (load-bearing) injects on `SessionState.swift`. Key
  checks: (a) still no wall-clock read — timestamp stays caller-supplied via the
  helper param; (b) `upsert` still happens on every applied event (the helper always
  upserts after mutate, matching the current arms which always upsert); (c) do NOT
  route these through `isTerminalAndMustNotResurrect` (metadata arms are phase-neutral
  and exempt — the rule lists only phase-changing paths).
- Behavior-neutrality proof: the #48 net (5 arms × 4 properties) + the existing
  end-to-end Cursor tests + full suite.

## Risks & unknowns
- **Ordering inside the helper**: current arms do `assign metadata` → `set updatedAt`
  → `upsert`. The helper does `mutate` (which assigns metadata) → `set updatedAt` →
  `upsert`. Identical order. The `mutate` closure must NOT set updatedAt itself
  (helper owns it) — keep closures to the metadata assignment only.
- **`inout` closure capturing `payload`**: each closure captures its own `payload`
  (value type), no aliasing risk. `mutate: (inout AgentSession) -> Void` is
  non-escaping by default — fine for a synchronous mutating call.
- **Don't over-generalize**: resist folding the metadata arms in with other arms
  that look similar but do more (e.g. `.activityUpdated` changes phase and routes
  through the terminal guard). ONLY the 5 pure metadata arms collapse.
- **TDD**: the #48 net already encodes the behavior; for this refactor the Red is to
  add ONE new assertion that would fail if the helper regressed, OR (since the arms
  are a pure relocation with the net already green) treat the #48 net as the
  characterization and mark the collapse `N/A(test)` proven by the net staying green +
  byte-behavior review. Prefer: add a small targeted test only if it covers a
  property the net doesn't. The net already covers all four properties per arm, so
  this is a genuine `N/A(test)` refactor (like the terminal-snapshot relocations) —
  no NEW failing-first test is meaningful; the net is the pre-registered proof.
- No human decision needed — scope is settled (collapse the 5, keep isEmpty per-arm,
  don't touch the terminal guard).
