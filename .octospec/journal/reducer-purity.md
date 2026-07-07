---
type: Journal
title: "Journal: reducer-purity"
description: Made SessionState deterministic (injectable clock) and fixed two liveness/guard correctness bugs
tags: ["reducer", "session-state", "correctness", "testability", "purity"]
timestamp: 2026-07-07T13:08:54Z
slug: reducer-purity
source: self
---

# Journal: reducer-purity

Second implemented slice of the `arch-quality-audit` discovery (findings #2, #11,
#12, #15). Independent of the bridge-security slice — different files, separate
branch, no chain.

## What was done

Four contained changes to `SessionState.swift`, all covered by new
`SessionStateTests` cases. The larger "fold all ~9 mutators into `apply`"
refactor (discovery #1) was deliberately deferred to its own slice.

1. **`answerQuestion` end-guard (#11)** — it now checks `isSessionEnded` and keeps
   an already-ended session `.completed` instead of unconditionally flipping to
   `.running`. This mirrors the existing `resolvePermission` guard and closes the
   "running-but-invisible phantom" hazard for the answer path (an out-of-order
   `sessionCompleted(isSessionEnd:)` arriving while a question is open).

2. **`markProcessLiveness` stale-count reset (#12)** — the non-hook polled branch
   captured `wasNotSeenCount` and now upserts whenever the count changes, not just
   when `isProcessAlive` flips. Previously an already-alive session whose
   `processNotSeenCount` reset nonzero → 0 on a later "alive" poll never got
   written back, leaving a stale count in the map. Behavior-preserving on the miss
   path (a miss always increments, so the count always changes there).

3. **`dismissSession` injectable clock (#2)** — gained `at timestamp: Date = .now`
   and stamps the supplied date instead of hardcoding `.now`. The app call site
   keeps the default (a legitimate external caller); the parameter makes the
   mutation deterministically testable, so `updatedAt` (and the `updatedAt`-keyed
   `sessions` sort) can be asserted exactly. `resolvePermission`/`answerQuestion`
   already took `at:`.

4. **Misplaced attribute cleanup (#15)** — a stray `@discardableResult` + doc
   comment sat between `removeInvisibleSessions`'s comment and `dismissSession`.
   Reattached: `dismissSession` carries its own comment; `removeInvisibleSessions`
   carries the `@discardableResult` it actually needs.

## Verification

- New tests: `answerQuestionDoesNotResurrectEndedSession`,
  `answerQuestionResumesLiveSession`, `markProcessLivenessPersistsNotSeenCountResetForAliveSession`,
  `dismissSessionUsesInjectedTimestamp`.
- Full gate green: `swift build` + `swift test` (349 tests, 41 suites) via
  `scripts/harness.sh ci`, exit 0, no new warnings.

## Learning

- **The reducer's real fragility is the visibility state space**
  (`phase × isSessionEnded × isProcessAlive × isHookManaged × isCodexAppSession`),
  enforced by scattered per-method guards. #11 and #12 were two symptoms of the
  same class: a mutator forgetting one dimension. The two terminal-guard blocks
  in `resolvePermission` and `answerQuestion` are now duplicated prose — a future
  slice (the #1 fold-into-`apply` refactor) should centralize the "don't
  resurrect an ended session" invariant rather than copy it per method. Captured
  as a load-bearing rule (`session-state-invariants`).
- **A reducer must not read the wall clock.** Timestamps that feed `updatedAt`
  (and therefore sort order / staleness) must be caller-supplied; `= .now`
  defaults are acceptable only at the outermost non-test call site.
