---
type: Task
title: "Task: perf-rollout-rewrite"
description: Detect in-place rewrite/compaction of a Codex rollout file so stale-offset garbage never reaches the reducer
tags: ["performance", "correctness", "transcript", "streaming", "codex"]
timestamp: 2026-07-08T13:30:15Z
# --- octospec extension fields ---
slug: perf-rollout-rewrite
upstream: arch-quality-audit-r2 (discovery finding #11)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-08T13:33:30Z
---

# Task: perf-rollout-rewrite

> Fifth slice of the `arch-quality-audit-r2` discovery. A small correctness +
> perf fix to the Codex rollout tailer's append-only assumption. Independent
> branch off `origin/main` (four prior slices merged).

## Goal

Fix the append-only assumption in `CodexRolloutWatcher.refresh`
(`CodexSessionTracking.swift:1477-1527`). Today it resets its byte `offset` **only**
when the file shrinks (`fileSize < observation.offset`, `:1489`). If Codex rewrites
or compacts a rollout file **in place to a size ≥ the stored offset**, the watcher
seeks to the now-stale `offset` (`:1496`) and feeds whatever bytes sit there —
mid-record garbage — into `extractNDJSONLines` → `CodexRolloutReducer.apply`,
producing wrong snapshot/UI state and wasted parse work on an always-on app.

Detect the rewrite by fingerprinting the file **head**: store a small head
fingerprint in `Observation`, captured whenever the offset is (re)established; on
each `refresh`, re-read the head and, if it differs from the stored fingerprint,
perform the same reset the shrink path already does (`offset = 0`, clear
`pendingBuffer`, fresh `snapshot`) before reading. A normal append never changes
the head, so this is inert on the hot path; it fires only on an actual rewrite,
replacement, or compaction (including same-size ones the shrink guard misses).

## Background

- `CodexRolloutWatcher` (`CodexSessionTracking.swift:1379`) polls known rollout
  files via a `DispatchSourceTimer`, tailing new bytes from a per-file `offset`
  held in `Observation` (`:1380-1386`). `makeObservation` (`:1533`) bootstraps the
  offset either at 0 (small files) or `fileSize - initialReadLimit` (large files,
  tail window) with a head-derived prompt snapshot.
- The reset block already exists (`:1489-1493`); this slice widens its trigger
  from "file shrank" to "file shrank OR its head changed."
- The fingerprint is a **bounded** head read (e.g. first ≤256 bytes) — consistent
  with the injected `transcript-reader-perf` rule ("stream, don't slurp"; no
  whole-file read). It must be captured at every point the offset is set so it
  stays consistent with what the offset assumes (init + both reset paths).
- Existing tests drive the watcher with real temp files + an `EventRecorder`
  actor (`CodexSessionTrackingTests.swift:843`, helpers `appendRolloutLine:1351`
  / `rolloutLine:1365`). There is currently **no** rewrite/truncation test — so
  the acceptance test is a genuine failing test against today's code.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`CodexRolloutWatcher.refresh`** (`CodexSessionTracking.swift:1477-1527`) — the
  reset guard + tail read; the change site. `[transcript] [streaming] [performance]`
- **`CodexRolloutWatcher.Observation`** (`:1380-1386`) — gains the head-fingerprint
  field. `[transcript]`
- **`CodexRolloutWatcher.makeObservation`** (`:1533-1561`) — must capture the
  fingerprint consistently with the bootstrapped offset. `[transcript]`
- **Existing tail/append/bootstrap behavior** — must be unchanged: normal appends,
  the tail-window bootstrap, and truncation reset all still work exactly as today.
  `[transcript]`

## Out of scope
- **FSEvents / replacing the poll model** (discovery #2) — a large refactor, not
  this slice.
- **The tmux subprocess fan-out memoization** (discovery #2) — separate slice.
- **Main-actor archived-sessions scan** (discovery #13/#23) — separate; the pure
  reconcile core is already tested.
- **Any change to the reducer, event shapes, `offset` bootstrap math, or the
  `initialReadLimit` tail-window sizing** beyond adding the fingerprint capture.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — an in-place rewrite at ≥ old size is detected and does NOT surface
  garbage.** Drive `CodexRolloutWatcher` against a temp rollout: let it tail some
  appended lines, then **rewrite the file in place** with different leading bytes
  and a total size ≥ the previous offset, containing new valid rollout lines. The
  watcher must reset and emit events reflecting the **new** content (e.g. the new
  last-user-prompt / completion), not stale-offset garbage or nothing. *(Testable:
  fails first — today the head change is undetected, so the new content at/after
  the stale offset is misread.)*
- **A2 — normal appends still tracked (no regression).** The existing
  append-tracking behavior still holds: appended lines after the initial sync
  produce the expected metadata/completion events. *(Testable: mirrors the current
  `codexRolloutWatcherTracksAppendedLines`; passes before and after — regression
  guard that the fingerprint check doesn't reset on plain appends.)*
- **A3 — truncation reset still works (no regression).** A file that shrinks below
  the stored offset still triggers a reset and re-reads from 0. *(Testable:
  characterizes the existing shrink path; guards against the fingerprint change
  breaking it.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
