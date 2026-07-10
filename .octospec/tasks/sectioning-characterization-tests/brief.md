---
type: Task
title: "Task: sectioning-characterization-tests"
description: Add characterization tests for AppModel's sectioning coverage gaps (.agent/.project/.none grouping, .attention sort) as the safety net for extracting the sectioning pipeline into SessionListPresenter
tags: ["app-model", "session-list", "test-coverage", "correctness"]
timestamp: 2026-07-10T04:10:00Z
# --- octospec extension fields ---
slug: sectioning-characterization-tests
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — sectioning C+A, test-net slice)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-10T03:39:39Z
---

# Task: sectioning-characterization-tests

> Slice C of the sectioning C+A (slice A = extract the sectioning pipeline into
> SessionListPresenter, blocked on this). **Test-only** — fills the coverage gaps
> that make the extraction safe. Independent branch off `origin/main`. See
> `.octospec/tasks/sectioning-characterization-tests/discovery.md`.

## Goal

`AppModel.islandSessionSections` groups the surfaced sessions four ways, but only
`.state` grouping and `.lastUpdate` sort are tested. Before slice A moves the
sectioning pipeline (`islandSessionSections` body / `sortIslandSessions` /
`stateGroupedSections` / `projectGroupName`) into `SessionListPresenter`, add
characterization tests for the untested branches, driven through the public
`model.islandSessionSections` so they stay green when the body moves behind a
delegate. Cover: `.agent` grouping, `.project` grouping (incl. `projectGroupName`
fallbacks), `.none` grouping, and `.attention` sort (identity).

## Not a Red→Green slice (why)

Characterization tests of already-correct behavior — they pass on `origin/main`
(marked `N/A(test-first)`). Verify's inverse job: confirm each is DISCRIMINATING
(would fail if slice A's extraction regressed that grouping/sort), not tautological.
Same shape as the manager/reducer nets.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`AppModel.islandSessionSections` + `sortIslandSessions` + `projectGroupName`** —
  the tests target these via the public `model.islandSessionSections`.
  `[app-model] [session-list]`
- **The tests only** — NO production change in this slice.

## Out of scope
- **Any production change** — tests exclusively.
- **The sectioning extraction** (slice A, blocked on this net).
- **`.state` grouping / `.lastUpdate` sort** — already covered; not re-tested.
- The closed-island derivations + bucketing (separate/done).

## Acceptance
<!-- Test-only slice: items are the coverage that must exist and pass on main. -->
- **A1 — `.agent` grouping.** With `islandSessionGroup = .agent` and surfaced sessions
  spanning ≥2 `AgentTool`s, `islandSessionSections` yields one section per tool that has
  ≥1 session, in `AgentTool.allCases` order, with id `agent-<rawValue>` and title
  `tool.displayName`; a tool with no sessions produces no section. *(Passes on main.)*
- **A2 — `.project` grouping + `projectGroupName`.** With `islandSessionGroup = .project`,
  sections are one per distinct `projectGroupName`, ordered by `localizedStandardCompare`;
  a session with a non-empty `jumpTarget.workspaceName` groups under it, and a session
  with no jumpTarget falls back (title's last `·` piece, else tool.displayName).
  Section id `project-<name>`, title `name`. *(Passes on main.)*
- **A3 — `.none` grouping.** With `islandSessionGroup = .none`, exactly one section
  (id `all`, title `island.section.sessions`) carrying all surfaced sessions.
  *(Passes on main.)*
- **A4 — `.attention` sort is identity.** With `islandSessionSort = .attention`,
  `sortIslandSessions` preserves the surfaced order (the section's sessions equal the
  surfaced order); contrasted against `.lastUpdate` reordering the same input.
  *(Passes on main.)*
- **A5 — discriminating + gate green.** Each test asserts a property that would FAIL
  if the corresponding branch regressed (wrong section ids/titles/order, wrong
  projectGroupName fallback, wrong single-section shape, or `.attention` reordering).
  `swift build` + `swift test` pass under the repo gate. *(N/A(test-first):
  coverage-only; Verify confirms the assertions are real.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
