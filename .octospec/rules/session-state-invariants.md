---
type: Rule
title: SessionState reducer invariants
description: Rules for changing SessionState — deterministic timestamps and the "don't resurrect an ended session" terminal guard on every phase mutation.
tags: ["reducer", "session-state", "correctness", "purity"]
timestamp: 2026-07-07T13:08:54Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: session-state-invariants
tier: repo
priority: 85
load_bearing: true
inject_when:
  paths:
    - "Sources/OpenIslandCore/SessionState.swift"
    - "Sources/OpenIslandCore/AgentSession.swift"
  touches: ["reducer", "session-state"]
source: self
supersedes: []
---

# SessionState reducer invariants

`SessionState` is the single reducer for session mutations. Its correctness rests
on a small state space enforced by guards; keep these invariants when changing it.

## Deterministic — never read the wall clock

- No mutation may read `Date.now` / `Date()` in its body. Timestamps that feed
  `updatedAt` (and therefore the `updatedAt`-keyed `sessions` sort and staleness)
  must be **caller-supplied** via an `at timestamp: Date` parameter.
- A `= .now` default is acceptable only so the outermost non-test caller can omit
  it; a test must always be able to drive every mutator with a fixed date and
  assert `updatedAt` exactly.

## Don't resurrect an ended session

- The visibility state space is
  `phase × isSessionEnded × isProcessAlive × isHookManaged × isCodexAppSession`.
  A session with `isSessionEnded == true` is terminal.
- Any mutator that sets `phase = .running` **must** first check `isSessionEnded`
  and keep the session `.completed` if it has ended. Flipping an ended session
  back to `.running` creates a "running but invisible" phantom that inflates
  `runningCount` while `isVisibleInIsland` is false. `resolvePermission` and
  `answerQuestion` both implement this guard — new actionable-resolution paths
  must too. (A future refactor should centralize this instead of duplicating the
  guard per method.)

## Persist what changed

- Liveness/count bookkeeping (`markProcessLiveness`) must `upsert` a session
  whenever a tracked field actually changes — including a `processNotSeenCount`
  that resets nonzero → 0 on an already-alive session — not only when
  `isProcessAlive` flips. A silently-dropped write leaves stale state in the map.
