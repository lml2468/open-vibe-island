---
type: Task
title: "Task: bridge-metadata-merging"
description: Extract BridgeServer's 9 pure metadata/tool/preview merge helpers into a static BridgeMetadataMerging namespace with direct unit tests for the per-agent clear/keep rules; byte-equivalent relocation off the biggest file
tags: ["dedup", "bridge", "session-metadata", "correctness"]
timestamp: 2026-07-10T03:10:00Z
# --- octospec extension fields ---
slug: bridge-metadata-merging
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — slice 1, safest cut)
source: self
revision: 1
approvals: []
---

# Task: bridge-metadata-merging

> First (safest, highest-ROI) cut on the #3 BridgeServer god-object (2,719 LOC).
> Extracts the verified-pure `merged*` helper family into a testable namespace and
> adds the direct coverage those helpers lack. The entangled per-agent handlers +
> `AgentHookHandler` protocol are a later, test-net-gated slice. Independent branch
> off `origin/main`. See `.octospec/tasks/bridge-metadata-merging/discovery.md`.

## Goal

BridgeServer holds 9 pure metadata/tool/preview merge helpers (verified zero
`self`/stored-state access) that are private methods only by historical accident:
- **OpenCode:** `mergedOpenCodeMetadata`, `mergedOpenCodeCurrentTool`,
  `mergedOpenCodeCurrentToolInputPreview`
- **Codex:** `mergedCodexMetadata`, `mergedCurrentTool`, `mergedCurrentCommandPreview`
- **Claude:** `mergedClaudeMetadata`, `mergedClaudeCurrentTool`,
  `mergedClaudeCurrentToolInputPreview`

Move them verbatim into a new `enum BridgeMetadataMerging` as `static func`s
(OpenIslandCore), and change each BridgeServer caller to
`BridgeMetadataMerging.mergedX(...)`. Byte-identical bodies; inner cross-calls
(metadata → its tool/preview sub-helpers) become unqualified static calls within the
enum. Mirrors the blessed `BridgeCodec` / already-`static`
`mergeJumpTargetPreservingExistingResolvedFields` pattern. Shrinks the biggest file
by ~150 LOC and makes the per-agent clear/keep rules directly unit-testable.

## Deliberately NOT in scope

- **`mergedClaudeQuestionInput`** — pure, but a different concern (builds question
  tool-input, not metadata merging); leave it in BridgeServer to keep the namespace
  cohesive.
- **`mergeJumpTargetPreservingExistingResolvedFields`** — already `static`, already
  directly tested; moving it is churn touching a passing test for no behavior gain.
  Leave it (fold later if ever).
- **The entangled per-agent handlers** (`handle*Hook`, `emit`/`send`/`pending*`),
  socket lifecycle, and the `AgentHookHandler` protocol — the later slice; needs a
  multi-agent test net first.
- No wire-format / model-enum / reducer change.

## Background

- **Injected rule:** `bridge-transport-invariants` (load-bearing, gates
  `BridgeServer.swift`). The mergers are PURE — no queue/socket/state — so the
  single-serial-queue and fail-open/closed invariants are untouched; moving them OUT
  reduces the rule's surface. No framing/model change.
- Coverage today: only the jumpTarget merge has a direct test; the 9 mergers are
  exercised only indirectly (Claude path via `ClaudeHooksTests`), so Codex/OpenCode
  tool-clear rules are thinly covered. This slice adds the missing direct tests.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `BridgeMetadataMerging`** — 9 static mergers; the per-field `update ?? existing`
  combines and the per-agent hookEventName clear/keep switches must be byte-identical
  to the originals. `[bridge] [session-metadata]`
- **BridgeServer callers** (`handleOpenCodeHook`/`handleCodexHook`/`handleClaudeHook`
  + the metadata mergers' internal sub-calls) — delegate to the namespace; no other
  change. `[bridge]`
- **The hook→metadata paths** — unchanged behavior (which fields survive, which tool
  state clears on which lifecycle event). `[bridge] [session-metadata]`

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — update-wins + field merge.** `BridgeMetadataMerging.mergedCodexMetadata`
  (and the Claude/OpenCode metadata mergers) combine per-field `update ?? existing`
  with the `initialUserPrompt` fallback; a present `update` field wins, an absent one
  falls back to `existing`. *(Testable: direct unit test. Fails first — stub.)*
- **A2 — tool/preview clear-on-lifecycle, per agent.** For each agent's tool/preview
  merger: a present `update` wins; with `update == nil`, a clearing hookEvent
  (Codex/OpenCode/Claude `.postToolUse`/`.stop`/… per that agent's set) returns `nil`,
  and a non-clearing event (`.preToolUse`/`.sessionStart`/…) returns `existing`. Pin
  at least one clear case and one keep case per agent. *(Testable: direct unit test.
  Fails first.)*
- **A3 — Claude subagent-lifecycle holds agentID/agentType.** `mergedClaudeMetadata`
  with a `hookEventName.isSubagentLifecycle == true` keeps `existing.agentID/agentType`
  (ignores update's); a non-lifecycle event takes `update ?? existing`. activeSubagents/
  activeTasks always preserved from existing. *(Testable: direct unit test.)*
- **A4 — BridgeServer delegates; behavior preserved.** After the move, BridgeServer
  defines none of the 9 mergers; each caller uses `BridgeMetadataMerging.*`. The
  existing bridge suites (`ClaudeHooksTests`, `GeminiHooksTests`,
  `BridgeServer*Tests`) pass unchanged, and the removed bodies are byte-equal to the
  namespace's (proven by the independent Verify's diff). *(Testable: existing suites +
  A1-A3 are the proof.)*
- **A5 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + existing bridge
  suites are the behavior-neutral proof for the relocation; A1-A3 are the new tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
