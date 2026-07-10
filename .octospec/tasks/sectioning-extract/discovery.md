---
type: Note
title: "Discovery: sectioning-extract"
description: Extract AppModel's sectioning pipeline (islandSessionSections body, sortIslandSessions, stateGroupedSections, projectGroupName) into SessionListPresenter static funcs, passing now in for determinism; second SessionListPresenter slice
tags: ["discovery"]
timestamp: 2026-07-10T04:30:00Z
# --- octospec extension fields ---
slug: sectioning-extract
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — sectioning C+A, slice A)
source: self
---

# Discovery: sectioning-extract

> The **Discover** phase output. Read-only. Slice A of the sectioning C+A; the net
> (`SessionSectioningTests`, .agent/.project/.none/.attention) landed in #52. Moves
> the sectioning bodies into the existing `SessionListPresenter`.

## Relevant files
- `Sources/OpenIslandApp/AppModel.swift`:
  - `islandSessionSections` (748-777) — computes `sortIslandSessions(surfacedSessions)`
    then switches on `islandSessionGroup` (.none/.state/.agent/.project). BODY moves;
    the public var stays as a thin delegate reading `surfacedSessions` + the three prefs.
  - `sortIslandSessions` (795-807) — `.attention` identity / `.lastUpdate` sort. MOVES.
  - `stateGroupedSections` (809-829) — approval/answer/running/done/idle; **reads `.now`
    twice** for the stale split. MOVES, taking `now: Date` as a param (determinism).
  - `projectGroupName` (831-844) — workspaceName → title-after-`·` → tool.displayName.
    MOVES.
- `Sources/OpenIslandApp/SessionListPresenter.swift` — existing enum (`buckets`,
  `displayPriority` from #51). New sectioning funcs join it.
- `Sources/OpenIslandApp/AppModelTypes.swift:128` — `IslandSessionSection { id, title,
  sessions }`; `IslandSessionGroup`/`IslandSessionSort` enums (same target).
- Net: `Tests/OpenIslandAppTests/SessionSectioningTests.swift` (#52) +
  `AppModelSessionListTests` (.state/.lastUpdate) — cover all branches.

## Existing behavior (to preserve exactly)
- `.none` → one section `all`/`island.section.sessions`. `.state` →
  `stateGroupedSections`. `.agent` → `AgentTool.allCases.compactMap` (empty omitted),
  id `agent-<rawValue>`, title `tool.displayName`. `.project` → distinct
  `projectGroupName`s sorted `localizedStandardCompare`, id `project-<name>`.
- `sortIslandSessions`: `.attention` returns input as-is; `.lastUpdate` sorts by
  `islandActivityDate` desc, tie-break title `localizedStandardCompare` asc.
- `stateGroupedSections`: 5 definitions (approval/answer/running/done/idle); done/idle
  split by `isStaleCompletedForIsland(at: now, threshold: staleThresholdSeconds)`.
  Currently `at: .now` — moving to a `now` param is behavior-neutral (same instant,
  now caller-supplied and testable).
- `projectGroupName`: exact fallback chain.

## Contracts & blast radius
- **Behavior-neutral extraction.** New presenter funcs:
  - `sections(from surfaced:group:sort:staleThresholdSeconds:now:) -> [IslandSessionSection]`
  - `sortSessions(_:by:) -> [AgentSession]` (the .attention/.lastUpdate switch)
  - `stateGroupedSections(from:staleThresholdSeconds:now:) -> [IslandSessionSection]`
  - `projectGroupName(for:) -> String`
  `islandSessionSections` on AppModel becomes a one-line delegate passing
  `surfacedSessions`, `islandSessionGroup`, `islandSessionSort`,
  `completedStaleThreshold.seconds`, `Date.now`. The other three private methods are
  removed from AppModel.
- **@Observable**: `islandSessionSections` stays an AppModel computed property reading
  `surfacedSessions`/prefs before delegating → observation unchanged. Views read
  `model.islandSessionSections` (IslandPanelView:561,611) — zero call-site churn.
- No rule strictly gates AppModel. The presenter is stateless static funcs. Passing
  `now` in removes the internal wall-clock read (a determinism improvement consistent
  with the reducer rule's spirit, though AppModel isn't the reducer).
- Coverage: #52 net (.agent/.project/.none/.attention) + AppModelSessionListTests
  (.state/.lastUpdate) exercise every branch through the public surface → behavior-
  neutral proof.

## Risks & unknowns
- **TDD**: the sectioning is covered end-to-end, but the presenter funcs are new
  callable surface — a genuine failing-first is available: stub the new funcs
  (empty/[]), add a couple of direct presenter unit tests (a grouping + the
  now-param'd stale split + projectGroupName fallback), confirm red, then move the
  bodies (green). Same pattern as the bucketing slice. The #52 + existing suites are
  the behavior-neutral proof for the delegation.
- **`now` threading**: `stateGroupedSections`'s two `.now` reads become one `now`
  param passed from `islandSessionSections`'s delegate (`Date.now`). Confirm both
  done/idle predicates use the SAME passed `now` (they must, for a consistent split).
- **`sortIslandSessions` naming**: presenter func named `sortSessions(_:by:)` to avoid
  implying island-specific state; body identical.
- No human decision — scope settled (move the 4 sectioning members; keep
  islandSessionSections as delegate; presenter stays a stateless enum).
