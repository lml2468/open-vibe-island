---
type: Note
title: "Discovery: sectioning-characterization-tests"
description: Add characterization tests for AppModel's sectioning coverage gaps (.agent/.project/.none grouping, .attention sort) as the net for extracting the sectioning pipeline into SessionListPresenter
tags: ["discovery"]
timestamp: 2026-07-10T04:05:00Z
# --- octospec extension fields ---
slug: sectioning-characterization-tests
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — sectioning C+A, test-net slice)
source: self
---

# Discovery: sectioning-characterization-tests

> The **Discover** phase output. Read-only. Slice C of the sectioning C+A: adds the
> coverage the sectioning pipeline lacks so slice A (extract into SessionListPresenter)
> is verifiable. Test-only, no production change. Same C+A shape as the manager and
> reducer nets.

## Relevant files (test targets — read-only here)
- `Sources/OpenIslandApp/AppModel.swift`:
  - `islandSessionSections` (748-777) — switches on `islandSessionGroup`:
    `.none` (single "all" section), `.state` (delegates `stateGroupedSections`),
    `.agent` (group by `AgentTool.allCases`, section id `agent-<rawValue>`, title
    `tool.displayName`), `.project` (group by `projectGroupName`, sorted by
    `localizedStandardCompare`, section id `project-<name>`).
  - `sortIslandSessions` (795-807) — `.attention` (identity) / `.lastUpdate`
    (islandActivityDate desc, tie-break title).
  - `stateGroupedSections` (809-829), `projectGroupName` (831-844).
- `Tests/OpenIslandAppTests/AppModelSessionListTests.swift` — harness:
  `model.islandSessionGroup = .state` / `model.islandSessionSort = .lastUpdate` are
  directly settable; `model.state = SessionState(sessions:)`; assert
  `model.islandSessionSections.map(\.id)` / `.sessions`. `listSession(id:phase:updatedAt:)`
  helper builds a `.codex` session with `jumpTarget.workspaceName == id`.

## Existing coverage vs gaps
- **Covered today**: `.state` grouping (`islandSessionSectionsGroupStaleCompletedIntoIdle`
  :314, `...KeepCompletedInDoneWhenStaleThresholdIsNever` :340) and `.lastUpdate` sort
  (`islandSessionListCanSortByLastUpdate` :355). `projectGroupName` is used only via
  the (untested) `.project` branch.
- **Gaps (this slice fills)**:
  - `.agent` grouping — group by tool, section ids/titles, empty tools omitted.
  - `.project` grouping — `projectGroupName` resolution (workspaceName → title-after-`·`
    → tool.displayName fallback) + section ordering by `localizedStandardCompare`.
  - `.none` grouping — single "all" section carrying all surfaced sessions.
  - `.attention` sort — identity (preserves surfaced order).

## Existing behavior (to pin)
- `.agent`: `AgentTool.allCases.compactMap` → a section per tool that has ≥1 session,
  in `allCases` order; id `agent-<rawValue>`, title `tool.displayName`.
- `.project`: distinct `projectGroupName`s sorted `localizedStandardCompare` asc; a
  section per name; id `project-<name>`, title `name`.
- `projectGroupName`: `jumpTarget.workspaceName` (trimmed, non-empty) wins; else the
  title's last `·`-separated piece (trimmed); else `tool.displayName`.
- `.none`: one section id `all`, title `island.section.sessions`, all sorted sessions.
- `.attention` sort returns the input order unchanged (surfaced order from bucketing).

## Contracts & blast radius
- **Characterization tests** — encode current behavior, pass on `origin/main`. They
  become the net for slice A, which will move these bodies into `SessionListPresenter`
  static funcs (and pass `now` in, since `stateGroupedSections` currently reads `.now`).
- Must drive through `model.islandSessionSections` (public surface) so they stay green
  when the body moves to the presenter behind a delegate.
- No production change; no rule to satisfy beyond deterministic assertions (avoid
  wall-clock sensitivity — for `.agent`/`.project`/`.none`/`.attention` the grouping
  is time-independent, so fixed dates suffice; the stale `.state` split is already
  covered and not re-tested here).

## Risks & unknowns
- **Multiple tools in fixtures**: `.agent` grouping needs sessions with different
  `AgentTool`s — build sessions with `.codex`, `.claudeCode`, etc. Confirm `tool` is
  a settable init param (it is — `AgentSession(... tool: ...)`).
- **`.project` ordering**: assert the `localizedStandardCompare` section order with
  workspace names that sort distinctly; include one session with no jumpTarget to hit
  the title/ tool fallback.
- **`.attention` identity**: to prove identity vs `.lastUpdate`, seed sessions whose
  surfaced order differs from activity-date order and assert `.attention` preserves
  surfaced order. Note surfaced order itself comes from bucketing (displayPriority) —
  keep the fixture simple (assert the section carries all sessions; identity is the
  key property, exact order is bucketing's concern already tested).
- No human decision — additive coverage; Plan just enumerates the gap tests.
