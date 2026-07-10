---
type: Task
title: "Task: sectioning-extract"
description: Extract AppModel's sectioning pipeline (islandSessionSections body, sortIslandSessions, stateGroupedSections, projectGroupName) into SessionListPresenter static funcs, passing now in for determinism; second AppModel god-object slice
tags: ["dedup", "app-model", "session-list", "correctness"]
timestamp: 2026-07-10T04:35:00Z
# --- octospec extension fields ---
slug: sectioning-extract
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — sectioning C+A, slice A)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-10T04:41:16Z
---

# Task: sectioning-extract

> Slice A of the sectioning C+A (slice C = `sectioning-characterization-tests`,
> merged #52). Second `SessionListPresenter` cut on the #8 AppModel god-object.
> Independent branch off `origin/main`. See
> `.octospec/tasks/sectioning-extract/discovery.md`.

## Goal

Move AppModel's sectioning pipeline — `islandSessionSections` body,
`sortIslandSessions`, `stateGroupedSections`, `projectGroupName` (748-844) — into the
existing `enum SessionListPresenter` as static funcs:
```swift
static func sections(from surfaced: [AgentSession], group: IslandSessionGroup, sort: IslandSessionSort, staleThresholdSeconds: TimeInterval, now: Date) -> [IslandSessionSection]
static func sortSessions(_ sessions: [AgentSession], by sort: IslandSessionSort) -> [AgentSession]
static func stateGroupedSections(from sessions: [AgentSession], staleThresholdSeconds: TimeInterval, now: Date) -> [IslandSessionSection]
static func projectGroupName(for session: AgentSession) -> String
```
`islandSessionSections` becomes a one-line delegate passing `surfacedSessions`,
`islandSessionGroup`, `islandSessionSort`, `completedStaleThreshold.seconds`,
`Date.now`. The three private methods are removed from AppModel. Bodies verbatim
except `stateGroupedSections`'s two internal `.now` reads become the passed `now`
param (behavior-neutral — same instant, now caller-supplied and testable).

## Deliberately NOT in scope
- **The bucketing pipeline** — already extracted (#51).
- **The closed-island derivations** (`islandClosed*`) + agents-grid ticket mutators —
  follow-up slice (untested + a side effect).
- **`surfacedSessions`/`recentSessions`/counts** — trivial delegates, stay.
- No view/call-site change (reads go through `model.islandSessionSections`), no
  coordinator/reducer/wire change.

## Background
- No load-bearing rule gates `AppModel.swift`; it's `@MainActor @Observable`. The
  presenter is stateless static funcs. Threading `now` in removes the internal
  wall-clock read (determinism improvement).
- **@Observable preserved**: `islandSessionSections` stays an AppModel computed
  property reading `surfacedSessions`/prefs before delegating; views observe through
  it, zero churn (grep: only `IslandPanelView` reads it).
- Coverage: the #52 net (.agent/.project/.none/.attention) + `AppModelSessionListTests`
  (.state/.lastUpdate) exercise every branch through the public surface.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionListPresenter`** (extended) — `sections`/`sortSessions`/
  `stateGroupedSections`/`projectGroupName`; must reproduce each grouping (.none/.state/
  .agent/.project), the sort modes, the 5-way state split with the stale done/idle
  boundary, and the projectGroupName fallback chain exactly. `[app-model] [session-list]`
- **AppModel `islandSessionSections`** — one-line delegate; the three private methods
  removed. `[app-model]`
- **The island section list** — unchanged behavior (grouping, ordering, section
  ids/titles). `[app-model] [session-list]`

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `sortSessions` modes.** `.attention` returns the input order unchanged;
  `.lastUpdate` sorts by `islandActivityDate` desc, tie-break title
  `localizedStandardCompare` asc. *(Testable: direct unit test. Fails first — stub.)*
- **A2 — `stateGroupedSections` split with injected `now`.** Produces
  approval/answer/running/done/idle sections (empty omitted), splitting completed into
  done vs idle by `isStaleCompletedForIsland(at: now, threshold: staleThresholdSeconds)`
  using the passed `now`. *(Testable: direct unit test with fixed `now`. Fails first.)*
- **A3 — `sections` grouping dispatch + `projectGroupName`.** `.none`→single `all`;
  `.agent`→per-tool in allCases order (empty omitted); `.project`→per distinct
  `projectGroupName` (workspaceName → title-after-`·` → tool.displayName) ordered
  `localizedStandardCompare`; `.state`→delegates the split. *(Testable: direct unit
  tests. Fail first.)*
- **A4 — AppModel delegates; behavior preserved.** `islandSessionSections` calls
  `SessionListPresenter.sections(...)` passing surfacedSessions + the 3 prefs + Date.now;
  `sortIslandSessions`/`stateGroupedSections`/`projectGroupName` removed from AppModel.
  The #52 net + `AppModelSessionListTests` pass unchanged. *(Testable: existing suites
  + A1-A3 are the proof.)*
- **A5 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + existing suites are
  the behavior-neutral proof; A1-A3 are the new direct tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
