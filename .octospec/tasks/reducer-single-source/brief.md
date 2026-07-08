---
type: Task
title: "Task: reducer-single-source"
description: Centralize the "don't resurrect an ended session" guard in SessionState (closing the permissionRequested/questionAsked gap) and dedupe the fork-list into isClaudeCodeFork
tags: ["reducer", "session-state", "correctness", "dedup"]
timestamp: 2026-07-08T12:02:34Z
# --- octospec extension fields ---
slug: reducer-single-source
upstream: arch-quality-audit-r2 (discovery findings #7, #19)
source: self
revision: 1
approvals: []
---

# Task: reducer-single-source

> Third slice of the `arch-quality-audit-r2` discovery. Tightens the reducer's
> terminal-session invariant into one place and removes a hand-copied tool list,
> using the existing `SessionStateTests` suite as the safety net. Independent
> branch off `origin/main` (both prior slices merged).

## Goal

Two changes to `SessionState.swift` / `AgentSession.swift` (discovery #7 + #19):

1. **Centralize the "don't resurrect an ended session" guard — and close the two
   paths that currently forget it.** The invariant ("a session with
   `isSessionEnded == true` must not be flipped back to `.running`") is hand-copied
   in three shapes (`apply(.activityUpdated)` `:99`, `resolvePermission` `:253`,
   `answerQuestion` `:303`) — and is **missing** from `apply(.permissionRequested)`
   (`:125`), `apply(.questionAsked)` (`:137`), and `apply(.actionableStateResolved)`
   (`:219`). An out-of-order `permissionRequested`/`questionAsked` for an ended
   session today resurrects it into a waiting phase that is invisible in the island
   yet actionable — the exact "phantom" class the `session-state-invariants` rule
   warns about. Introduce one private helper (e.g. `isTerminal(_ session:)` or a
   guard applied uniformly) so every phase-changing path in `apply` and the two
   public resolvers share **one** expression of the invariant, and the currently
   unguarded paths become guarded. This is the centralization the existing rule
   explicitly defers ("A future refactor should centralize this").

2. **Dedupe the Claude-fork tool list into `AgentTool.isClaudeCodeFork`.**
   `isClaudeCodeFork` (`AgentSession.swift:65`:
   `.claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI`) is currently
   **dead code** (zero usages), while `resolvePermission` hand-inlines the same set
   **plus `.geminiCLI`** twice (`SessionState.swift:262,272`). Replace those two
   inlined switches with `isClaudeCodeFork`, **preserving the existing `.geminiCLI`
   behavior** (i.e. `tool.isClaudeCodeFork || tool == .geminiCLI`) so the summary
   strings are byte-for-byte unchanged for every tool.

## Background

- `SessionState` is a pure `struct` reducer with a thorough suite
  (`Tests/OpenIslandCoreTests/SessionStateTests.swift`, 43 `@Test`) including a
  "Regression: out-of-order events must not resurrect ended sessions" section
  (`:1445`) that today covers only `activityUpdated`, `resolvePermission`,
  `answerQuestion` — **not** the `permissionRequested`/`questionAsked` paths this
  slice fixes.
- **Injected rule (must follow):** `session-state-invariants` (load-bearing) —
  deterministic timestamps, the terminal guard on every `phase = .running` (extend
  to every phase-changing path), and persist-what-changed. This slice makes its
  "centralize the guard" note real.
- **Behavior-preservation is the core risk.** #2 must not change any summary
  string; #1 must not change behavior for sessions that have NOT ended (a normal
  permission/question on a live session still transitions exactly as today).

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionState.apply(_:)`** phase-changing cases — `activityUpdated` `:88`,
  `permissionRequested` `:125`, `questionAsked` `:137`, `sessionCompleted` `:149`,
  `actionableStateResolved` `:219`. The guard centralization touches these.
  `[reducer] [session-state]`
- **`SessionState.resolvePermission` / `answerQuestion`** (`:237,:284`) — the two
  public resolvers that already guard; must route through the shared helper and
  keep identical outputs. `[reducer] [session-state]`
- **`AgentTool.isClaudeCodeFork`** (`AgentSession.swift:65`) — the helper being
  adopted; its membership defines correctness of the dedup. `[session-state]`
- **Invariants that must not regress:** `runningCount` / `liveSessionCount` /
  `isVisibleInIsland` semantics; deterministic `updatedAt` (no wall-clock read);
  every existing `SessionStateTests` case still passes. `[reducer]`

## Out of scope
- **Folding the 8 non-`apply` public mutators into `apply`** (the larger
  single-entry-point refactor). This slice centralizes the *terminal guard* and
  the *fork list* only; the mutator surface stays as-is (a bigger, riskier slice).
- **`isTrackedLiveSession`'s 10-way `||` tool chain** (`AgentSession.swift:511`) —
  a separate dedup; not touched here.
- **The 5 mirrored `*SessionMetadataUpdated` cases / `AgentEvent` Codable
  hand-mirroring** (discovery #10) — separate slice.
- No change to any summary string, event shape, or public method signature.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — an out-of-order `permissionRequested` does not resurrect an ended
  session.** Given a session with `isSessionEnded == true` and `phase == .completed`,
  `apply(.permissionRequested(...))` leaves it `.completed` / `isSessionEnded ==
  true` and does NOT set `.waitingForApproval`. *(Testable: fails first — currently
  transitions to `.waitingForApproval`.)*
- **A2 — an out-of-order `questionAsked` does not resurrect an ended session.**
  Same, for `apply(.questionAsked(...))` → stays `.completed`, not
  `.waitingForAnswer`. *(Testable: fails first.)*
- **A3 — a normal `permissionRequested`/`questionAsked` on a LIVE (not-ended)
  session still transitions as before** (→ `.waitingForApproval` /
  `.waitingForAnswer`, prompt set). *(Testable: guards against over-broad guarding;
  passes before and after — behavior preservation.)*
- **A4 — `isClaudeCodeFork` is used by the reducer and summary strings are
  unchanged for every tool.** For an approved permission on each of
  `.claudeCode, .qoder, .qwenCode, .factory, .codebuddy, .kimiCLI, .geminiCLI`
  the summary is the fork/gemini string; for `.openCode` and a `default` tool the
  summaries are unchanged; and `isClaudeCodeFork` has at least one non-test usage
  in `Sources/`. *(Testable: assert exact summary strings per tool; the "used"
  check can be a test that exercises the reducer path. Fails first only if a
  regression is introduced — this item is primarily a preservation guard, so it is
  written to lock current strings before the refactor.)*
- **A5 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
