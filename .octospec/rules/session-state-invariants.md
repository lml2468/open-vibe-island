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
- Any mutator that sets a non-terminal `phase` (`.running` / `.waitingForApproval`
  / `.waitingForAnswer`) **must** first check the terminal guard and keep the
  session `.completed` if it has ended. Flipping an ended session back creates a
  "running/actionable but invisible" phantom that inflates the counts while
  `isVisibleInIsland` is false.
- The invariant is now expressed in **one** place —
  `SessionState.isTerminalAndMustNotResurrect(_:)`. Every phase-changing path
  routes through it: `apply(.activityUpdated)`, `apply(.permissionRequested)`,
  `apply(.questionAsked)`, `resolvePermission`, `answerQuestion`. Do NOT re-inline
  `session.isSessionEnded` in a new mutator — call the helper, and add any new
  phase-changing path to that list. (`apply(.actionableStateResolved)` is
  implicitly safe: it early-returns unless the session is already in a waiting
  phase, which an ended `.completed` session never is.)

## Persist what changed

- Liveness/count bookkeeping (`markProcessLiveness`) must `upsert` a session
  whenever a tracked field actually changes — including a `processNotSeenCount`
  that resets nonzero → 0 on an already-alive session — not only when
  `isProcessAlive` flips. A silently-dropped write leaves stale state in the map.
