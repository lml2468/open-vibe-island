---
type: Journal
title: "Journal: perf-battery"
description: Fixed transcript-reading perf/correctness bugs — Codex usage OOM slurp, Claude fractional-second timestamps, O(n^2) line extraction, per-line formatter allocation
tags: ["performance", "correctness", "transcript", "streaming", "memory"]
timestamp: 2026-07-08T04:07:37Z
slug: perf-battery
source: self
---

# Journal: perf-battery

Fifth implemented slice of the `arch-quality-audit` discovery (findings #13, #14,
#15). First slice to run under the quality gates landed in `quality-gates`
(warnings-as-errors + SwiftLint strict).

## What was done

Each fix had a correct sibling already in the codebase, so the changes are
low-risk and behavior-preserving (except the #13 timestamp, an intended
correctness fix).

1. **Codex usage OOM slurp (#14)** — `CodexUsageLoader.loadLatestSnapshot` no
   longer reads whole rollout files with `String(contentsOf:)`; it streams via
   chunked `FileHandle.read(upToCount:)` + the shared line extractor, mirroring
   `CodexRolloutDiscovery` / `ClaudeTranscriptDiscovery`. "Last matching line
   wins" and newest-first candidate order are preserved.
2. **Claude fractional-second timestamps (#13)** — a default
   `ISO8601DateFormatter()` never parsed Claude's `…:SS.mmmZ` stamps, so
   `updatedAt` silently fell back to file mtime (recency/ordering/prune ran off
   mtime). New shared `TranscriptTimestamp.parse` tolerates fractional AND
   whole-second forms; the Claude parse site and `codexRolloutParseTimestamp`
   both route through it.
3. **O(n^2) line extraction + formatter hoisting (#15)** — the three identical
   `extractCompleteLines`/`completeLines` copies did `Data.removeSubrange(...idx)`
   per line (front-removal is O(remaining) → quadratic per chunk). New shared
   `extractNDJSONLines` does a single forward scan and one buffer compaction,
   behavior-identical (empty lines skipped, trailing partial retained). All three
   sites delegate to it. `ISO8601DateFormatter` allocations are now `static let`
   instead of per-line/per-call.

## Verification

- New `TranscriptStreamingTests` (line extraction: multi-line, trailing partial,
  empty lines, leading newline, chunked-append == single-shot, empty; timestamps:
  fractional, whole-second, nil/garbage). Existing `CodexUsageTests` /
  `CodexSessionTrackingTests` confirm behavior-identity.
- Full gate green: `harness.sh ci` (378 tests) with warnings-as-errors + SwiftLint
  strict (0 violations), exit 0.

## Learning

- **`static let ISO8601DateFormatter` trips the Swift 6 concurrency gate** (it's
  not `Sendable`). Correct resolution is `nonisolated(unsafe)` with a rationale —
  the formatter is thread-safe for `date(from:)` once `formatOptions` is set and
  is never mutated afterward. Do NOT revert to per-call allocation (that defeats
  the perf fix). The quality-gates warnings-as-errors caught this at build time,
  as intended.
- **`enumerateLines` → `\n`-only extractor is a safe narrowing for machine JSONL.**
  `String.enumerateLines` also splits on `\r\n` / Unicode separators; agent
  rollout/transcript files are `\n`-delimited machine output, so the newline-only
  extractor is equivalent (confirmed by the existing usage tests).
- **Front-removal on `Data` is O(n).** Any "consume lines from a growing buffer"
  loop must scan once and drop the consumed prefix once, not `removeSubrange` per
  line. Captured as the `transcript-reader-perf` rule; also relevant to
  `BridgeCodec.decodeLines`, which has the same pattern (left for a future pass —
  its frames are small and capped).
