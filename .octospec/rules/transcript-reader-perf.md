---
type: Rule
title: Transcript reader performance
description: Rules for the always-on transcript/rollout readers — stream don't slurp, linear line extraction, hoisted formatters, tolerant timestamp parsing.
tags: ["performance", "transcript", "streaming", "memory"]
timestamp: 2026-07-08T04:07:37Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: transcript-reader-perf
tier: repo
priority: 80
load_bearing: false
inject_when:
  paths:
    - "Sources/OpenIslandCore/ClaudeTranscriptDiscovery.swift"
    - "Sources/OpenIslandCore/CodexSessionTracking.swift"
    - "Sources/OpenIslandCore/CodexUsage.swift"
    - "Sources/OpenIslandCore/CursorTranscriptReader.swift"
    - "Sources/OpenIslandCore/NDJSONLineExtractor.swift"
    - "Sources/OpenIslandCore/TranscriptTimestamp.swift"
  touches: ["transcript", "streaming", "performance"]
source: self
supersedes: []
---

# Transcript reader performance

These readers run at startup and continuously on an always-on menu-bar app, over
files that can be tens of MB. Keep them cheap.

## Stream, don't slurp

- Never read a whole transcript/rollout with `String(contentsOf:)` /
  `Data(contentsOf:)`. Read in chunks (`FileHandle.read(upToCount:)`) and process
  line-by-line, flushing a final unterminated line. `CodexUsageLoader`,
  `CodexRolloutDiscovery`, and `ClaudeTranscriptDiscovery` are the reference.

## Linear line extraction

- Use the shared `extractNDJSONLines(from:)` to split a growing buffer into
  lines. Do NOT hand-roll a `while buffer.firstIndex(of: \n) { …
  buffer.removeSubrange(...idx) }` loop — front-removal on `Data` is O(remaining),
  making the loop O(n^2) per chunk. Scan once, compact the prefix once.
- `\n`-only splitting is correct for these machine-written JSONL files; do not
  switch to `String.enumerateLines` (it also splits on `\r\n`/Unicode separators
  and forces a full-string decode).

## Hoisted, tolerant timestamp parsing

- Parse transcript timestamps via the shared `TranscriptTimestamp.parse` — it
  handles both fractional-second (`…:SS.mmmZ`) and whole-second forms. A plain
  `ISO8601DateFormatter()` without `.withFractionalSeconds` silently fails on
  Claude timestamps and callers fall back to file mtime (wrong recency/prune).
- `ISO8601DateFormatter` is expensive to allocate — keep it a `static let`, never
  per-line/per-call. It is not `Sendable`; annotate the static with
  `nonisolated(unsafe)` (it's only ever read via `date(from:)` after config, which
  is thread-safe) rather than reverting to per-call allocation. See
  [[ci-quality-gates]] — warnings-as-errors will flag the un-annotated form.

## Resume-from-offset tailers: check file identity, not just size

- A byte-offset tailer (`CodexRolloutWatcher`) assumes the file is append-only.
  Resetting only when the file **shrinks** (`fileSize < offset`) misses an
  in-place rewrite/compaction to a size ≥ the stored offset: the offset stays
  numerically valid but now points into unrelated bytes, feeding mid-record
  garbage into the reducer. Also detect a **head change** via a cheap bounded
  fingerprint (≤256 leading bytes) captured whenever the offset is established;
  reset (offset→0, clear buffer/snapshot, re-seed fingerprint) when the head
  differs.
- Seed the fingerprint at **every** offset-establishing path. The dangerous one is
  a tail-window bootstrap that sets a **non-zero** offset — forgetting to seed it
  there makes the first poll see an empty→actual head "change" and reset to 0,
  re-reading the whole large file and defeating the tail window (a perf regression
  hiding inside a correctness fix).
- Keep the identity read bounded (fixed head slice), never a whole-file slurp —
  same stream-don't-slurp discipline as above.
