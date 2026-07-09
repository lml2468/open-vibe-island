---
type: Task
title: "Task: missing-gemini-metadata-merge"
description: Fix the latent bug where SessionDiscoveryCoordinator drops discovered Gemini metadata on rediscovery — add mergeGeminiMetadata mirroring the other four mergers and wire it into merge()
tags: ["bug", "session-metadata", "gemini", "correctness"]
timestamp: 2026-07-09T13:35:00Z
# --- octospec extension fields ---
slug: missing-gemini-metadata-merge
upstream: arch-quality-audit-r2 (surfaced while scoping cluster C #10)
source: self
revision: 1
approvals: []
---

# Task: missing-gemini-metadata-merge

> A correctness fix (behavior change), not a refactor. Discovery/finding:
> `.octospec/tasks/missing-gemini-metadata-merge/discovery.md` (filed during the
> `agentevent-sessionid` slice). Independent branch off `origin/main`.

## Goal

`SessionDiscoveryCoordinator.merge(discovered:into:)`
(`Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift`) reconciles per-agent
metadata for Codex/Claude/OpenCode/Cursor (`merged.codexMetadata = mergeCodexMetadata(...)`,
etc. at ~L250-253) but has **no `geminiMetadata` handling at all** — no
`mergeGeminiMetadata` function and no assignment in `merge()`. Because `merge()`
starts from `var merged = existing`, the result silently keeps `existing`'s
`geminiMetadata` and **discards whatever the rediscovered session carried**. For a
Gemini session, newer transcript/prompt/assistant-message metadata found on
rediscovery is lost.

Add a `mergeGeminiMetadata(_:_:)` mirroring the existing four (same nil-guard
skeleton, per-field `discovered ?? existing` combine with `initialUserPrompt`
special-cased), and wire `merged.geminiMetadata = mergeGeminiMetadata(existing.geminiMetadata,
discovered.geminiMetadata)` into `merge()`.

## Background

- `GeminiSessionMetadata` (`GeminiHooks.swift`) has 5 fields: `transcriptPath`,
  `initialUserPrompt`, `lastUserPrompt`, `lastAssistantMessage`,
  `lastAssistantMessageBody`, plus `isEmpty`. The merge must follow the established
  per-field convention: `discovered.X ?? existing.X`, with
  `initialUserPrompt = existing.initialUserPrompt ?? discovered.initialUserPrompt ??
  discovered.lastUserPrompt` (matching Codex/OpenCode/Cursor), and return
  `merged.isEmpty ? nil : merged`.
- `AgentSession.geminiMetadata` already exists and is set elsewhere (the reducer's
  `.geminiSessionMetadataUpdated` arm); only the rediscovery MERGE path omits it.
- No injected rule strictly gates `SessionDiscoveryCoordinator` (it's app-layer, not
  the reducer/bridge), but the change must preserve the merge contract the other
  four follow — nil-in handling, isEmpty→nil, newer-field precedence.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionDiscoveryCoordinator.merge(discovered:into:)`** — add the
  `merged.geminiMetadata = mergeGeminiMetadata(...)` line. `[session-metadata]`
- **New `mergeGeminiMetadata(_:_:)`** — mirrors the four existing mergers'
  skeleton + Gemini's 5 fields. `[session-metadata]`

## Out of scope
- The other four mergers and the reducer arms (unchanged).
- Making the merge block exhaustive/data-driven so a future agent can't be omitted —
  a good idea (noted in the finding) but a separate refactor; this slice is the
  minimal correctness fix.
- Any `AgentEvent`/wire-format/reducer change.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — rediscovery preserves newer Gemini metadata (the bug).** Given an existing
  tracked session with partial `geminiMetadata` (e.g. only `initialUserPrompt`) and
  a rediscovered session (same id, newer) carrying additional Gemini fields
  (e.g. `lastAssistantMessage`, `transcriptPath`), `mergeDiscoveredSessions`
  produces a session whose `geminiMetadata` contains BOTH the existing
  `initialUserPrompt` AND the discovered new fields. *(Testable: fails on current
  code — discovered fields are dropped because merge() never reads them.)*
- **A2 — existing Gemini metadata is not lost when discovered has none.** Existing
  session has `geminiMetadata`, discovered has `nil` → merged keeps existing's.
  *(Testable.)*
- **A3 — nil/empty handling matches the other mergers.** Both nil → nil; a merge
  whose combined result is empty → nil (via `isEmpty`). *(Testable.)*
- **A4 — the fix mirrors the established convention + gate green.** `mergeGeminiMetadata`
  follows the same nil-guard + `discovered ?? existing` + `initialUserPrompt`
  fallback + `isEmpty ? nil` shape as `mergeCodexMetadata`; `swift build` +
  `swift test` pass under the repo gate. Other agents' merge behavior is unchanged.
  *(N/A(test) for the "mirrors convention" clause — proven by review; A1-A3 are the
  behavioral tests; the gate is the neutrality proof for the other four.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
