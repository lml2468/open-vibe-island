---
type: Note
title: "Finding: missing mergeGeminiMetadata in SessionDiscoveryCoordinator"
description: Latent bug — Gemini session metadata is dropped across a rediscovery merge because SessionDiscoveryCoordinator merges Codex/Claude/OpenCode/Cursor but omits Gemini
tags: ["bug", "finding", "session-metadata", "gemini"]
timestamp: 2026-07-09T13:20:00Z
# --- octospec extension fields ---
slug: missing-gemini-metadata-merge
upstream: arch-quality-audit-r2 (surfaced while scoping cluster C #10)
source: self
status: open
---

# Finding: missing `mergeGeminiMetadata`

> Surfaced (not fixed) during the `agentevent-sessionid` slice scouting. Recorded
> here so it isn't lost; needs its own discover→plan→approve cycle because it is a
> **behavior change**, not a refactor.

## What

`SessionDiscoveryCoordinator` (`Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift`,
merge block ~L250-253) merges rediscovered per-agent metadata for **Codex, Claude,
OpenCode, and Cursor** — but there is **no `mergeGeminiMetadata`** and Gemini is
omitted from the merge block. There are `merge<Agent>Metadata` functions for the
other four (`mergeOpenCodeMetadata` ~L262, `mergeCursorMetadata` ~L285,
`mergeCodexMetadata` ~L327, `mergeClaudeMetadata` ~L350) but none for Gemini.

## Impact

When a Gemini session is rediscovered and merged with an existing tracked session,
its `geminiMetadata` is not carried through the merge path the way the other four
agents' metadata is. Depending on the merge-block structure this means Gemini
metadata is either dropped or not reconciled on rediscovery — a latent correctness
gap for Gemini users specifically.

## Why it's a separate slice (not fixed in `agentevent-sessionid`)

- It is a **behavior change** (adds/alters what metadata survives a merge), not a
  mechanical dedup — so it needs its own brief + acceptance + approval, and likely a
  characterization test asserting the current (buggy) behavior first, then the fix.
- It touches `SessionDiscoveryCoordinator` merge logic, not the `AgentEvent`
  sessionID extraction that slice was scoped to.
- Fixing it silently inside a refactor would violate the "don't smuggle behavior
  changes into a dedup" discipline.

## Suggested next step

A dedicated slice: (1) write a test reproducing the drop (install+track a Gemini
session, rediscover, assert metadata currently lost), (2) add `mergeGeminiMetadata`
mirroring the other four and wire it into the merge block, (3) confirm the test now
shows metadata preserved. Consider whether the coordinator's per-agent merge block
should itself be made exhaustive (e.g. driven by a per-agent list) so a future agent
can't be silently omitted again.
