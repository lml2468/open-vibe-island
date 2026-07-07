---
type: Task
title: "Task: reducer-purity"
description: Make SessionState deterministic and fix its two liveness/guard correctness bugs — injectable clock, answerQuestion end-guard, markProcessLiveness reset
tags: ["reducer", "session-state", "correctness", "testability", "purity"]
timestamp: 2026-07-07T12:51:51Z
# --- octospec extension fields ---
slug: reducer-purity
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-07T13:03:07Z
---

# Task: reducer-purity

> Second slice of the `arch-quality-audit` discovery (see
> `.octospec/tasks/arch-quality-audit/discovery.md`, findings #2, #11, #12, #15).
> Scoped to the **purity & correctness core** of `SessionState`: make the reducer
> deterministic (injectable clock) and fix its two known state-machine bugs. The
> larger "fold all ~9 mutators into `apply`" architectural change (discovery #1)
> is deliberately a separate future slice — see Out of scope.

## Goal
`SessionState` is documented and relied on as a pure, deterministic reducer, but
today it reads wall-clock time and has two invariant gaps. This slice closes
those without changing observable app behavior:

1. **Injectable clock (determinism) — discovery #2.** `resolvePermission`
   (`SessionState.swift:240`) and `answerQuestion` (`:287`) default
   `at timestamp: Date = .now`, and `dismissSession` (`:454`) hardcodes
   `session.updatedAt = .now`. A reducer that reads the wall clock is
   non-deterministic: `updatedAt` (and therefore the `sessions` sort order, which
   is `updatedAt`-keyed) varies per run and can't be asserted exactly in tests.
   Make every mutation timestamp caller-supplied: give `dismissSession` an
   `at timestamp: Date` parameter and thread a real timestamp from all call
   sites. Keep the `= .now` *default* only where an external (non-test) caller
   genuinely has no better value, but ensure the type is fully testable with an
   injected clock (a test must be able to drive every mutator with a fixed date).

2. **`answerQuestion` end-guard (correctness) — discovery #11.**
   `answerQuestion` (`:284-299`) unconditionally sets `phase = .running`, unlike
   `resolvePermission` (`:253-257`) which refuses to resurrect an already-ended
   session (the "running but invisible phantom" hazard documented at `:93-101`,
   `:249-252`). Add the same `isSessionEnded` guard to `answerQuestion`: if the
   session has ended, record the answer's effect but keep it `.completed` /
   terminal rather than flipping it back to `.running`.

3. **`markProcessLiveness` stale-count reset (correctness) — discovery #12.** In
   the non-hook branch (`:423-438`), when a session was already alive and its
   `processNotSeenCount` is reset from a nonzero value back to 0, no `upsert`
   happens (the code only upserts when `isProcessAlive` changed, or when
   not-alive with count ≥ 1). The stale count persists in the map. Ensure a
   count that actually changes is always persisted.

4. **Misplaced attribute cleanup — discovery #15.** A stray `@discardableResult`
   + doc comment at `SessionState.swift:446-449` is attached to the wrong method
   (`dismissSession`) rather than `removeInvisibleSessions`. Fix the attachment /
   remove the misplacement so each attribute documents the method it precedes.

## Background
- `SessionState` is a `struct` keyed by `sessionsByID`; `sessions` sorts by
  `updatedAt` desc then title. The visibility state space
  (`phase × isSessionEnded × isProcessAlive × isHookManaged × isCodexAppSession`)
  is enforced by scattered guards — the discovery flagged this as the fragile
  core; #11/#12 are two concrete symptoms.
- Clock call sites to thread a timestamp through (from grep):
  - `AppModel.resolvePermission`/`answerQuestion`/`dismissSession`
    (`AppModel.swift:1390, 1423, 1434, 1445`).
  - `BridgeServer.localState.resolvePermission` (`BridgeServer.swift:439`).
  - Tests already pass explicit dates in several places
    (`SessionStateTests.swift:170, 180, 1538`).
- `markProcessLiveness` is called from `ProcessMonitoringCoordinator.swift:295`
  and covered by `SessionStateTests.swift:42-136`.
- This slice must respect the `bridge-transport-invariants` rule only if it
  touches bridge files; `BridgeServer.swift:439` is a call-site update (passing a
  timestamp), not a transport-contract change.

## Load-bearing list
<!-- Existing behaviors/contracts this change touches. -->
- **`SessionState.resolvePermission` / `answerQuestion` / `dismissSession`** —
  signature/timestamp behavior; all app + bridge call sites.
- **`SessionState.answerQuestion` phase transition** — adding the
  `isSessionEnded` terminal guard (must match `resolvePermission`'s semantics at
  `:253-257`).
- **`SessionState.markProcessLiveness`** (`:365-442`) — the non-hook liveness
  branch and its `changed` set / `upsert` discipline; consumed by
  `ProcessMonitoringCoordinator` and the `sessions` derived views.
- **`sessions` sort / `updatedAt` ordering** — the observable consequence of the
  clock change; island ordering must be unchanged for identical inputs.
- **`SessionStateTests`** — the existing reducer suite (the safety net; extend it).
- **`ProcessMonitoringCoordinator`** (`:295`, `:354`) — caller of the liveness
  mutators; must still compile and behave identically.

## Out of scope
- **Discovery #1** — folding the ~9 public mutators into a single `apply(_:)`
  (or an internal command enum). That is a larger architectural refactor with
  blast radius into `ProcessMonitoringCoordinator` and the bridge; it gets its
  own slice. This slice keeps the current method surface.
- The `_cachedSessionBuckets` time-dependent staleness in `AppModel` (discovery
  #6, UI-layer) — different subsystem.
- Optimistic-local-mutation vs bridge-echo reconciliation redesign (discovery #7).
- Any change to `AgentEvent`, the bridge transport, or hook parsing.
- Per-tool metadata / tool-list duplication (#10, #11-maint) — separate cleanup.

## Acceptance
<!-- Machine-checkable where possible. -->
- **A1 — deterministic timestamps.** `SessionState` can be driven end-to-end with
  an injected fixed `Date`: a test constructs a session, calls
  `resolvePermission`, `answerQuestion`, and `dismissSession` each with an
  explicit `at:` date, and asserts `updatedAt` equals exactly that date (no
  `.now` leakage). `dismissSession` has an `at timestamp: Date` parameter.
- **A2 — no wall-clock read on the covered mutators.** No `.now` / `Date()` is
  invoked inside `resolvePermission`, `answerQuestion`, or `dismissSession`
  except as an explicit parameter default; grep-assertable in review.
- **A3 — answerQuestion end-guard.** A test where a session receives an
  out-of-order `sessionCompleted(isSessionEnd: true)` while a question is open,
  then `answerQuestion`, asserts the session stays terminal
  (`isSessionEnded == true`, not resurrected to `.running` / visible) — mirroring
  the existing `resolvePermission` end-guard test.
- **A4 — liveness reset persisted.** A test drives `markProcessLiveness` so a
  non-hook, already-alive session's `processNotSeenCount` goes nonzero → 0 on a
  later alive poll, and asserts the stored session's `processNotSeenCount == 0`
  (no stale count). Existing liveness tests still pass.
- **A5 — no behavior regression.** All existing `SessionStateTests` pass
  unchanged (except where they now pass an explicit date); island sort order for
  identical inputs is unchanged.
- **A6 — attribute cleanup.** `@discardableResult` is attached to the method it
  documents; `dismissSession` and `removeInvisibleSessions` each carry the
  correct attribute/comment.
- **A7 — gate green.** `zsh scripts/harness.sh ci` (`swift build` + `swift test`)
  passes; no new warnings.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
