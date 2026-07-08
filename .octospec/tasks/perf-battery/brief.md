---
type: Task
title: "Task: perf-battery"
description: Fix the transcript-reading perf/correctness bugs — Codex usage OOM slurp, Claude fractional-second timestamps, O(n^2) line extraction, per-line formatter allocation
tags: ["performance", "correctness", "transcript", "streaming", "memory"]
timestamp: 2026-07-08T02:48:47Z
# --- octospec extension fields ---
slug: perf-battery
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-08T03:42:26Z
---

# Task: perf-battery

> Fifth slice of the `arch-quality-audit` discovery (see
> `.octospec/tasks/arch-quality-audit/discovery.md`, findings #13, #14, #15).
> Scoped to the **contained transcript-reading perf & correctness bugs** — the
> ones with clear in-repo reference implementations and no lifecycle risk. The
> polling→FSEvents rework (#16) is deliberately a separate future slice; see Out
> of scope.

## Goal
The always-on transcript readers have three concrete defects that cost memory,
battery, or correctness. Each has a correct sibling already in the codebase to
mirror:

1. **Codex usage OOM slurp (#14).** `CodexUsageLoader.loadLatestSnapshot`
   (`CodexUsage.swift:124`) reads an entire rollout JSONL into memory with
   `String(contentsOf:)`, then enumerates lines — the exact pattern the streaming
   readers (`CodexRolloutDiscovery`, `ClaudeTranscriptDiscovery`) were refactored
   away from to avoid multi-GB startup peaks. Worse, it iterates *all* rollout
   candidates newest-first and fully slurps each until one yields a usage line;
   the newest file often lacks `token_count`, so several large files get fully
   read. Convert it to a streaming read (chunked `FileHandle` + line extraction,
   like the other readers). Reading tail-first / stopping early is a bonus but not
   required — the required fix is: no whole-file `String(contentsOf:)`.

2. **Claude fractional-second timestamps (#13).**
   `ClaudeTranscriptDiscovery.swift:107` uses a default `ISO8601DateFormatter()`
   with no `.withFractionalSeconds`, but Claude transcript timestamps carry
   fractional seconds (`…:SS.mmmZ`). Every parse returns nil, so `updatedAt`
   silently falls back to file mtime — session recency/ordering and the prune
   cutoff run off mtime, not real activity. Add `.withFractionalSeconds` (and
   `.withInternetDateTime`), mirroring `codexRolloutParseTimestamp`
   (`CodexSessionTracking.swift:1708-1709`). A robust parser should also still
   accept timestamps *without* fractional seconds (some lines may omit them).

3. **O(n^2) line extraction + per-line allocation (#15).**
   `extractCompleteLines`/`completeLines` (`ClaudeTranscriptDiscovery.swift:218`,
   `CodexSessionTracking.swift:549` and `:1552`) do
   `buffer.firstIndex(of: \n)` + `buffer.removeSubrange(...idx)` in a loop.
   Front-removal on `Data` is O(remaining), so a large chunk with many short JSONL
   lines is quadratic. Rewrite to a single forward scan that slices all lines and
   compacts the buffer once (drop the consumed prefix a single time), preserving
   the exact same outputs (including: empty lines skipped, no trailing partial
   line consumed). Also hoist the per-line/per-call `ISO8601DateFormatter`
   allocations (#7 in the audit's perf list) to `static let`s so they aren't
   rebuilt for every line/every call on the hot path.

## Background
- Streaming reference: `ClaudeTranscriptDiscovery` and `CodexRolloutDiscovery`
  already use `fileHandle.read(upToCount: streamingChunkSize)` + a buffer + a
  final-trailing-line flush. `CodexUsageLoader` is the one that regressed to a
  slurp — bring it in line.
- Timestamp reference: `codexRolloutParseTimestamp` sets
  `[.withInternetDateTime, .withFractionalSeconds]` and is the correct pattern.
- The three `extractCompleteLines`/`completeLines` copies are structurally
  identical; the rewrite should keep them behavior-identical (this slice does NOT
  merge them into one shared helper — that's a dedup concern; it just fixes the
  algorithm in place, or extracts a single private helper if that's cleaner
  without expanding scope).
- `ISO8601DateFormatter` is documented as expensive to allocate; it is
  thread-safe for read once configured, so a `static let` is safe under the
  readers' usage.
- Verified on current `main` (post #17–19): `CodexUsage.swift:124` slurp;
  `ClaudeTranscriptDiscovery.swift:107` default formatter; the three extractor
  sites with `removeSubrange(...idx)` in a loop.

## Load-bearing list
- **`CodexUsageLoader.loadLatestSnapshot` / `snapshot(from:)`**
  (`CodexUsage.swift`) — the read path; must still return the *latest* usage
  snapshot in a file (last matching line wins) and still try candidates
  newest-first.
- **`ClaudeTranscriptDiscovery` timestamp parse** (`:107`) — `updatedAt`
  derivation; changing it shifts session recency/ordering & the 24h prune cutoff
  toward *correct* values (activity time, not mtime). This is an intended
  behavior change; ensure ordering tests reflect real timestamps.
- **`extractCompleteLines` (Claude) / `extractCompleteLines` + `completeLines`
  (Codex)** — the NDJSON framing for all transcript reads; outputs must be
  byte-for-byte identical (same lines, same skipping, same partial-line
  retention). These feed the reducers.
- **The streaming readers' hot path** — formatter/regex hoisting must not change
  parse results.
- **Existing tests**: `CodexUsageTests`, `CodexSessionTrackingTests`,
  `ClaudeTranscriptDiscovery`-related tests, `SessionStateTests` ordering — the
  safety net.

## Out of scope
- **#16 polling → FSEvents/DispatchSource** rework of `CodexRolloutWatcher` /
  `SessionDiscoveryCoordinator` / `ProcessMonitoringCoordinator` intervals — a
  watcher-lifecycle change with real behavioral risk (coalescing, missed events,
  permissions); its own slice.
- **#5 process-discovery subprocess fan-out** (`ActiveAgentProcessDiscovery`
  serial `lsof`/`tmux`) — separate perf slice.
- **#8 rollout append-only assumption**, **#12 O(n·m) liveness matching**, **#13
  TimedCache purge** (audit LOW items) — not here.
- Merging the three `extractCompleteLines` copies into one shared type (dedup
  slice #6). Fix the algorithm in place; a small private helper is OK but no
  cross-file abstraction.
- Any behavior change to what a snapshot/line *means* — only how fast/how much
  memory it takes to produce it (except the #13 timestamp, which is a correctness
  fix).

## Acceptance
- **A1 — no whole-file slurp in usage loading.** `CodexUsageLoader` no longer
  calls `String(contentsOf:)` (grep-assertable); it reads via chunked
  `FileHandle` streaming. A test with a multi-line rollout fixture returns the
  same latest snapshot it does today.
- **A2 — Claude fractional-second timestamps parse.** A test feeds a Claude
  transcript line with a fractional-second ISO timestamp
  (`2026-04-02T04:03:44.500Z`) and asserts the parsed `updatedAt` equals that
  instant (not the file mtime). A timestamp *without* fractional seconds still
  parses.
- **A3 — line extraction is linear and behavior-identical.** The rewritten
  `extractCompleteLines`/`completeLines` produce exactly the same `[String]` as
  before for representative inputs (multiple lines in one chunk, empty lines,
  a trailing partial line left in the buffer, CRLF-free JSONL). Add a unit test
  asserting the outputs and that the residual buffer holds only the unterminated
  tail.
- **A4 — formatters hoisted.** `ISO8601DateFormatter` (and any recompiled
  `NSRegularExpression` on these hot paths) are `static let`, not constructed
  per line/per call (grep-assertable).
- **A5 — no behavior regression.** All existing tests pass; transcript-derived
  session ordering for identical inputs is unchanged except where it now reflects
  real activity timestamps (A2).
- **A6 — gate green.** `zsh scripts/harness.sh ci` passes (warnings-as-errors +
  SwiftLint strict, per the quality-gates slice); no new warnings.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
