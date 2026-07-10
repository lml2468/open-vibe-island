---
type: Task
title: "Task: session-list-presenter"
description: Extract AppModel's bucketing pipeline (computeSessionBuckets body + displayPriority) into a stateless SessionListPresenter enum with direct unit tests, passing monitoring.liveAttachmentKey as a closure seam; first AppModel god-object slice
tags: ["dedup", "app-model", "session-list", "correctness"]
timestamp: 2026-07-10T03:40:00Z
# --- octospec extension fields ---
slug: session-list-presenter
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — slice 1, bucketing pipeline)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-10T03:23:35Z
---

# Task: session-list-presenter

> First cut on the #8 AppModel god-object (1,859 LOC). Extracts the fully
> test-covered bucketing pipeline into a `SessionListPresenter`; the sectioning and
> closed-island derivations are follow-up slices (they have coverage gaps needing
> characterization tests first). Independent branch off `origin/main`. See
> `.octospec/tasks/session-list-presenter/discovery.md`.

## Goal

AppModel's session bucketing pipeline — `computeSessionBuckets()` (1688-1723) and
`displayPriority(for:now:)` (1725-1778) — is pure logic over `state.sessions` + the
`completedStaleThreshold` pref + one coordinator call (`monitoring.liveAttachmentKey`).
Extract it into a new stateless `enum SessionListPresenter` (OpenIslandApp):
```swift
static func displayPriority(for session: AgentSession, now: Date, staleThresholdSeconds: TimeInterval) -> Int
static func buckets(
    from sessions: [AgentSession],
    now: Date,
    staleThresholdSeconds: TimeInterval,
    liveAttachmentKey: (AgentSession) -> String?
) -> (primary: [AgentSession], overflow: [AgentSession])
```
`computeSessionBuckets` becomes a one-line delegate passing `state.sessions`,
`Date.now`, `completedStaleThreshold.seconds`, and
`{ monitoring.liveAttachmentKey(for: $0) }`. The cached `sessionBuckets` accessor and
the `surfacedSessions`/`recentSessions` delegates stay on AppModel. Byte-equivalent
behavior; makes the ranking + dedup directly unit-testable with a fixed `now`.

## Deliberately NOT in scope
- **The cached `sessionBuckets` accessor** (1679-1686) + its invalidation in
  `state.didSet`/`appearancePreferencesDidChange` — cache lifecycle is AppModel's;
  keep it, delegate only `computeSessionBuckets`'s body.
- **The sectioning pipeline** (`islandSessionSections`/`sortIslandSessions`/
  `stateGroupedSections`/`projectGroupName`) — follow-up slice; `.project`/`.agent`
  grouping branches lack tests (add char tests first).
- **The closed-island derivations** (`islandClosed*`) + the agents-grid ticket
  mutators — follow-up; untested + one has a side effect.
- No view/call-site change (all reads go through `model.*` delegates), no coordinator
  change, no reducer/wire change.

## Background
- No load-bearing rule gates `AppModel.swift`; it's `@MainActor @Observable`. The
  presenter is stateless static funcs — usable from MainActor, no isolation of its own.
- **@Observable preserved**: `sessionBuckets`/`surfacedSessions`/`recentSessions` stay
  as AppModel computed properties that read `state`/prefs before delegating, so view
  observation is unchanged. No view reads the private pipeline directly (grep-confirmed).
- Coverage today: the pipeline is covered end-to-end via AppModel
  (`AppModelSessionListTests` lines 34/94/167/266) — this slice adds DIRECT presenter
  tests on top.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `SessionListPresenter`** — `buckets` + `displayPriority` static funcs; must
  reproduce the exact ranking (score desc, tie-break islandActivityDate desc then
  title), the visible/non-subagent/liveAttachmentKey-dedup primary walk, the overflow
  filter, and the full displayPriority scoring. `[app-model] [session-list]`
- **AppModel `computeSessionBuckets`** — becomes a one-line delegate passing the 4
  inputs; `sessionBuckets` cache + `surfacedSessions`/`recentSessions` unchanged.
  `[app-model]`
- **The island session list** — unchanged behavior (which sessions are primary vs
  overflow, in what order). `[app-model] [session-list]`

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `displayPriority` scoring preserved.** For representative sessions,
  `SessionListPresenter.displayPriority(for:now:staleThresholdSeconds:)` returns the
  same score the AppModel logic produced: attention/running/tool/jumpTarget/phase
  contributions, the stale-completed penalty (fresh completed outranks stale
  completed), and the age buckets. *(Testable: direct unit test with fixed `now`.
  Fails first — stub.)*
- **A2 — `buckets` ranking + primary/overflow split.** Higher-priority sessions rank
  first; ties break by islandActivityDate desc then title; primary contains visible
  non-subagent sessions, overflow the rest (non-subagent); an ended/invisible session
  is excluded from primary. *(Testable: direct unit test. Fails first.)*
- **A3 — `buckets` dedups by liveAttachmentKey.** Two sessions returning the same
  `liveAttachmentKey` (injected closure) yield only the first (higher-ranked) in
  primary; a `nil` key never dedups. *(Testable: direct unit test with a stub closure.
  Fails first.)*
- **A4 — AppModel delegates; behavior preserved.** `computeSessionBuckets` calls
  `SessionListPresenter.buckets(...)` with `state.sessions`, `Date.now`,
  `completedStaleThreshold.seconds`, `{ monitoring.liveAttachmentKey(for: $0) }`;
  `displayPriority` is removed from AppModel; `sessionBuckets` cache +
  `surfacedSessions`/`recentSessions` unchanged. The existing `AppModelSessionListTests`
  (island-list dedup, distinct-threads, fresh-vs-stale ordering) pass unchanged.
  *(Testable: existing suite + A1-A3 are the proof.)*
- **A5 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + existing suite are
  the behavior-neutral proof; A1-A3 are the new tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
