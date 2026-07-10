---
type: Journal
title: "Journal: session-list-presenter"
description: Extracted AppModel's bucketing pipeline (computeSessionBuckets + displayPriority) into a stateless SessionListPresenter enum with direct unit tests, injecting liveAttachmentKey as a closure seam; first AppModel god-object cut, −83 LOC
tags: ["dedup", "app-model", "session-list", "correctness"]
timestamp: 2026-07-10T03:55:00Z
slug: session-list-presenter
source: self
---

# Journal: session-list-presenter

First cut on the #8 AppModel god-object from the `arch-quality-audit-r2` audit. See
`.octospec/tasks/session-list-presenter/brief.md` (r1, approved).

## What was done

Moved AppModel's session bucketing pipeline — `computeSessionBuckets()` body +
`displayPriority(for:now:)` — into a new stateless `enum SessionListPresenter` of
static funcs (`buckets`, `displayPriority`). The one coordinator dependency
(`monitoring.liveAttachmentKey`) is injected as a `(AgentSession) -> String?` closure
so the presenter needs no AppModel/coordinator reference, and the `completedStaleThreshold`
pref is passed as a `TimeInterval` param. `computeSessionBuckets` is now a one-line
delegate; `displayPriority` is removed from AppModel. The cached `sessionBuckets`
accessor (+ its invalidation) and the `surfacedSessions`/`recentSessions` delegates
stay on AppModel, so `@Observable` tracking and all view call-sites are unchanged.
AppModel: 1,859 → 1,776 LOC (−83).

## Verification

- New `SessionListPresenterTests` (6): A1 displayPriority scoring (attention >
  completed, fresh > stale, live-process adds), A2 buckets ranking + primary/overflow
  split excluding invisible/ended, A3 liveAttachmentKey dedup (shared key keeps
  higher-ranked; nil never dedups) — the FIRST direct tests of the ranking (previously
  exercised only end-to-end via AppModel).
- TDD trail: `red:` (57719ea) stubbed the presenter (0/empty) → all 6 failed on
  assertion; Green (06cd043) filled verbatim bodies + delegated; `git diff red..green
  -- Tests/` = 0 bytes.
- Independent Verify (fresh context) PASS, no findings — byte-diffed the original
  against the presenter (sort closure, primary walk, overflow filter, and EVERY
  displayPriority score term identical; the only substitutions the two intended seams),
  confirmed `displayPriority` removed with no orphan, cache + `surfacedSessions`/
  `recentSessions` + `@Observable` + views untouched. Gate green: `harness.sh ci`
  (503 tests), exit 0; the pre-existing `AppModelSessionListTests` net passes unchanged.

## Learning

- **A god-object with prior decomposition is a facade + pure-derivation problem, not
  a monolith.** AppModel already had 5 coordinators extracted; the scout found the
  remaining bulk is orchestration (defensibly AppModel's) plus pure computed
  derivations. The highest-ROI cut is a pure-derivation cluster that ALREADY has a
  test net — here the bucketing pipeline, covered by `AppModelSessionListTests`. That
  let the extraction proceed with a real Red→Green (new direct presenter tests) while
  the existing suite proved behavior-neutrality, no new net needed.
- **Inject the one impure dependency as a closure to keep the extracted unit pure.**
  `computeSessionBuckets` was pure except `monitoring.liveAttachmentKey(for:)`. Passing
  that as a `(AgentSession) -> String?` param (rather than importing the coordinator)
  keeps `SessionListPresenter` a stateless, dependency-free function of its args —
  trivially testable with a stub closure, and the dedup seam is now explicit at the
  call site. Same family as `HookGroupSanitizer`'s `isManaged` and the reducer arms'
  `mutate` closures.
- **Keep the public computed vars as thin delegates to preserve `@Observable`.** The
  safe shape for moving logic out of an `@Observable` `@MainActor` model: the public
  `sessionBuckets`/`surfacedSessions`/`recentSessions` stay as AppModel computed
  properties that read `state`/prefs before delegating, so view observation is
  unchanged and there is zero call-site churn. Only the BODY moves. Verify this by
  confirming the diff touches no view files.
- **AppModel #8 remaining (sequenced by test coverage):** the sectioning pipeline
  (`islandSessionSections`/`sortIslandSessions`/`stateGroupedSections`/`projectGroupName`)
  — needs `.project`/`.agent` grouping characterization tests first (C+A); then the
  closed-island derivations (`islandClosed*`) — untested + one has a grid-ticket side
  effect. The trivial cleanups (hex-color extensions → own file; watch-relay) are
  independent low-value moves.
