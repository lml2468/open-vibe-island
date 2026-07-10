---
type: Note
title: "Discovery: bridge-metadata-merging"
description: Extract BridgeServer's 9 pure metadata/tool/preview merge helpers into a static BridgeMetadataMerging namespace, adding direct unit tests as they move; byte-equivalent relocation off the biggest file
tags: ["discovery"]
timestamp: 2026-07-10T03:05:00Z
# --- octospec extension fields ---
slug: bridge-metadata-merging
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — slice 1, safest cut)
source: self
---

# Discovery: bridge-metadata-merging

> The **Discover** phase output. Read-only. First (safest) cut on the #3
> BridgeServer god-object (2,719 LOC). Extracts the verified-pure `merged*` helper
> family; the entangled per-agent handlers + `AgentHookHandler` protocol are a later,
> test-net-gated slice.

## Relevant files
- `Sources/OpenIslandCore/BridgeServer.swift` — the 9 pure merge helpers to move
  (verified zero `self`/stored-state access via grep):
  - **OpenCode:** `mergedOpenCodeMetadata` (1694), `mergedOpenCodeCurrentTool`
    (1717), `mergedOpenCodeCurrentToolInputPreview` (1734)
  - **Codex:** `mergedCodexMetadata` (2049), `mergedCurrentTool` (2072),
    `mergedCurrentCommandPreview` (2398)
  - **Claude:** `mergedClaudeMetadata` (2089), `mergedClaudeCurrentTool` (2364),
    `mergedClaudeCurrentToolInputPreview` (2381)
  - Callers: `handleOpenCodeHook` (~1670), `handleCodexHook` (~1904),
    `handleClaudeHook` (~2025), plus the metadata mergers call their own tool/preview
    sub-helpers internally.
- `Sources/OpenIslandCore/BridgeServer.swift:2716` — `ClaudeHookEventName.isSubagentLifecycle`
  extension used by `mergedClaudeMetadata`; module-internal, accessible from a new
  file in the same target.
- `Sources/OpenIslandCore/BridgeTransport.swift` — the blessed precedent: `BridgeCodec`
  (enum namespace of static framing funcs). `mergeJumpTargetPreservingExistingResolvedFields`
  is already `static` (BridgeServer:1977) with a direct test — the proof this pattern works.
- `Tests/OpenIslandCoreTests/BridgeServerJumpTargetMergeTests.swift` — template for
  testing a static merger without a live server.

## Existing behavior (what to preserve exactly)
Each merger takes `(existing:, update:, hookEventName:)` (metadata) or
`(existing:, update:, hookEventName:)` (tool/preview) and returns the merged value:
- **metadata mergers**: build a new `<Agent>SessionMetadata` with per-field
  `update ?? existing` (initialUserPrompt has the `existing ?? update ?? update.lastUserPrompt`
  fallback; Claude's agentID/agentType are held when `hookEventName.isSubagentLifecycle`;
  activeSubagents/activeTasks preserved from existing).
- **tool/preview mergers**: `if let update return update`; else the hookEventName
  decides clear-vs-keep — a per-agent switch (`.postToolUse/.stop/…` → nil,
  `.preToolUse/.sessionStart/…` → existing). These clear-on-lifecycle rules are the
  behaviorally-important part and differ per agent (Codex/OpenCode/Claude have
  different event enums + different clearing sets).

## Contracts & blast radius
- **Pure relocation** — move the 9 funcs verbatim into `enum BridgeMetadataMerging`
  as `static func`s; each caller in BridgeServer becomes
  `BridgeMetadataMerging.mergedX(...)`. Inner cross-calls (metadata → tool/preview)
  become unqualified static calls within the enum. Byte-identical bodies.
- `bridge-transport-invariants` (load-bearing) injects on `BridgeServer.swift`. These
  mergers are PURE (no queue/socket/state), so the single-serial-queue invariant is
  unaffected — moving them out actually reduces the surface the rule must worry about.
  No wire-format/model-enum change.
- Coverage today: only `mergeJumpTargetPreservingExistingResolvedFields` has a direct
  test. The 9 mergers are exercised only indirectly via `ClaudeHooksTests` (Claude
  path) — Codex/OpenCode tool-clear rules are thinly covered. Moving them to a
  testable namespace lets us add direct unit tests (the "test net added as it moves").

## Divergence to PRESERVE / leave out
- **`mergedClaudeQuestionInput` (2553)** is pure too, but it builds a
  `ClaudeHookJSONValue` tool-input from a question response — a DIFFERENT concern
  (question answering), not metadata merging. Leave it in BridgeServer to keep the new
  namespace cohesive (metadata/tool/preview only). Note, don't move.
- **`mergeJumpTargetPreservingExistingResolvedFields`** — already `static`, already
  tested; moving it is churn that touches a passing test for no behavior gain. Leave
  it (optionally fold later). Note as a deliberate non-goal.
- Everything entangled (handlers, emit/send, pending*, socket) — out of scope; that's
  the later `AgentHookHandler` slice.

## Risks & unknowns
- **TDD shape**: this is a relocation, but the mergers are (mostly) untested, so a
  real failing-first is available and worthwhile: create `BridgeMetadataMerging` with
  STUB static funcs returning wrong values, write unit tests for the clear/keep rules
  per agent (postToolUse→nil, preToolUse→keep, update-wins), confirm red on assertion,
  then move the real bodies (green). Same pattern as `ConfigManifestStore`. This adds
  the missing direct coverage AND proves the move.
- **Naming collision**: `mergedCurrentTool`/`mergedCurrentCommandPreview` (Codex) have
  no agent prefix; inside the namespace that's fine, but confirm no other same-named
  symbol. (Claude/OpenCode variants are prefixed.)
- **isSubagentLifecycle** must remain reachable — it's a module-internal extension, so
  a same-target file can call `hookEventName.isSubagentLifecycle`. Confirm at Green.
- No human decision — scope settled (9 pure mergers; leave questionInput + jumpTarget).
