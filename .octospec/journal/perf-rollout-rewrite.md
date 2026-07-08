---
type: Journal
title: "Journal: perf-rollout-rewrite"
description: CodexRolloutWatcher detects in-place rollout rewrite/compaction via a bounded head fingerprint, so stale-offset garbage never reaches the reducer
tags: ["performance", "correctness", "transcript", "streaming", "codex"]
timestamp: 2026-07-08T13:45:00Z
slug: perf-rollout-rewrite
source: self
---

# Journal: perf-rollout-rewrite

Fifth implemented slice of the `arch-quality-audit-r2` discovery (finding #11).
Chosen over the other perf findings (#2 tmux memoization, #13/#23 main-actor
scan) as the tightest correctness+perf fix with a real failing-first test.

## What was done

`CodexRolloutWatcher.refresh` (`CodexSessionTracking.swift`) reset its byte
`offset` only when the file shrank (`fileSize < offset`). An in-place
rewrite/compaction to a size ≥ the stored offset went undetected → the watcher
seeked to a now-stale offset and fed mid-record garbage into
`CodexRolloutReducer`. Fix: `Observation` gained a bounded (≤256-byte) head
fingerprint, captured wherever the offset is established — both `makeObservation`
paths (small-file offset 0 **and** the tail-window non-zero offset) and the reset
block. `refresh` now resets when the file shrank **or** the head changed, then
updates the stored fingerprint so it doesn't re-reset. Append and truncation paths
are unchanged.

## Verification

- New `CodexSessionTrackingTests` (3): A1 in-place rewrite ≥ old size surfaces the
  NEW content (failed first on today's code — only stale first-generation events
  appeared), A2 plain appends still tracked (fingerprint doesn't reset on append),
  A3 truncation still resets.
- TDD trail: `red:` committed the tests (A1 fails, A2/A3 pass as regression
  guards); Green touched only the source (`git diff red..green -- Tests/` = 0
  bytes). Independent Verify (fresh context) reproduced A1 failing at the red
  tree, PASS with no findings.
- Full `CodexSessionTrackingTests` (26, incl. the tail-window bootstrap tests that
  exercise the touched non-zero-offset path) green; gate green: `harness.sh ci`
  (414 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **A byte-offset tailer needs a same-file check, not just a size check.**
  `fileSize < offset` catches truncation but not an in-place rewrite/compaction to
  ≥ the old size — the file identity changed while the offset stayed "valid"
  numerically. A cheap bounded head fingerprint (or inode) is the missing "is this
  still the same file's byte-stream I was tailing?" signal. Applies to any
  resume-from-offset reader. Captured in the `transcript-reader-perf` rule.
- **When adding a fingerprint/identity field, seed it at EVERY offset-establishing
  path — the non-obvious one bites.** The tail-window bootstrap sets a *non-zero*
  offset; forgetting to seed its fingerprint there would make the first poll see
  an empty→actual head "change" and reset to 0, re-reading the whole large file
  and defeating the tail window (a perf regression masquerading as a correctness
  fix). The small-file path (offset 0) is forgiving; the tail path is not.
- **Bound the identity read.** The fingerprint is a fixed ≤256-byte read, never a
  whole-file slurp — consistent with the reader's stream-don't-slurp invariant.
  Documented the 256-byte-head limitation inline (a rewrite with a byte-identical
  first 256 bytes is missed; real rollouts change the leading `session_meta`
  line, so it differs in practice).
