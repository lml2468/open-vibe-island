---
type: Note
title: "Discovery: session-list-presenter"
description: Extract AppModel's bucketing pipeline (computeSessionBuckets body + displayPriority) into a stateless SessionListPresenter enum, passing monitoring.liveAttachmentKey as a closure seam; first SessionListPresenter slice
tags: ["discovery"]
timestamp: 2026-07-10T03:35:00Z
# --- octospec extension fields ---
slug: session-list-presenter
upstream: arch-quality-audit-r2 (discovery finding #8, god-object AppModel — slice 1, bucketing pipeline)
source: self
---

# Discovery: session-list-presenter

> The **Discover** phase output. Read-only. First cut on the #8 AppModel god-object
> (1,859 LOC). Extracts the fully-test-covered bucketing pipeline; sectioning and
> closed-island derivations are follow-up slices (they have coverage gaps —
> `.project`/`.agent` grouping + all `islandClosed*` — needing characterization
> tests first).

## Relevant files
- `Sources/OpenIslandApp/AppModel.swift`:
  - `sessionBuckets` (1679-1686) — CACHED accessor (`_cachedSessionBuckets`,
    invalidated in `state.didSet:50` and `appearancePreferencesDidChange:421`).
    STAYS on AppModel (cache lifecycle).
  - `computeSessionBuckets()` (1688-1723) — ranks `state.sessions` by
    `displayPriority`, walks visible non-subagent sessions claiming live-attachment
    keys (dedup), splits primary/overflow. Calls `monitoring.liveAttachmentKey(for:)`
    (1711) — the one coordinator dependency. BODY moves to the presenter.
  - `displayPriority(for:now:)` (1725-1778) — pure scoring: reads session
    presentation helpers + `completedStaleThreshold.seconds`. MOVES.
- `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift:1217` —
  `func liveAttachmentKey(for session: AgentSession) -> String?`. Effectively pure
  (reads `session.jumpTarget` + a static terminal whitelist), but lives on the
  coordinator — pass it into the presenter as a `(AgentSession) -> String?` closure
  seam so the presenter needn't import the coordinator.
- `Sources/OpenIslandApp/AgentSession+Presentation.swift:341` —
  `isStaleCompletedForIsland(at:threshold:)`, `islandPresence(at:)`,
  `islandActivityDate`, `currentToolName` — session-level helpers the scoring uses;
  already module-visible, callable from a presenter in the same target.
- `Tests/OpenIslandAppTests/AppModelSessionListTests.swift` — bucketing coverage:
  `islandListDeduplicatesSessionsSharingTheSameLiveGhosttyTerminal` (94, the
  liveAttachmentKey dedup), `islandListKeepsDistinctCodexAppThreadsInTheSameWorkspace`
  (167), `freshCompletedSessionsSortAheadOfV8StaleCompletedSessions` (266, the
  displayPriority ordering), `islandListSessionsOnlyIncludeLiveAttachedSessions` (34).

## Existing behavior (to preserve exactly)
- `computeSessionBuckets`: sort by `displayPriority` desc, tie-break by
  `islandActivityDate` desc then title `localizedStandardCompare` asc; primary =
  visible, non-subagent, first-claimant of each `liveAttachmentKey`; overflow =
  ranked minus primary IDs, non-subagent. `Date.now` read once at the top.
- `displayPriority`: the exact additive scoring (process-alive/presence, attention,
  currentToolName, jumpTarget, phase, stale-completed penalty, age buckets).
- The cached `sessionBuckets` accessor + its two invalidation points are unchanged.

## Contracts & blast radius
- **Behavior-neutral extraction.** New `enum SessionListPresenter` (OpenIslandApp)
  with:
  - `static func displayPriority(for:now:staleThresholdSeconds:) -> Int`
  - `static func buckets(from:now:staleThresholdSeconds:liveAttachmentKey:) -> (primary:, overflow:)`
  `computeSessionBuckets` on AppModel becomes a one-line delegate passing
  `state.sessions`, `Date.now`, `completedStaleThreshold.seconds`, and
  `{ monitoring.liveAttachmentKey(for: $0) }`. `sessionBuckets` cache accessor +
  `surfacedSessions`/`recentSessions` delegates stay.
- **@Observable**: `sessionBuckets`/`surfacedSessions`/`recentSessions` remain AppModel
  computed properties reading `state`/prefs before delegating, so view observation is
  unchanged. Views read `model.islandListSessions`/`surfacedSessions`/`recentSessions`
  — none read the private pipeline directly (grep confirms), zero call-site churn.
- No injected rule strictly gates AppModel; it's `@MainActor @Observable`. The
  presenter is stateless (static funcs), so it's trivially usable from MainActor and
  needs no isolation of its own.
- Determinism: `Date.now` is read in AppModel's delegate (as today) and passed in, so
  the presenter itself is a pure function of its args — testable with a fixed `now`.

## Risks & unknowns
- **TDD**: the pipeline is covered end-to-end via AppModel, but the presenter is new
  callable surface — a genuine failing-first is available and worthwhile: stub
  `SessionListPresenter.displayPriority`/`buckets` returning wrong values, add direct
  unit tests (ordering, the liveAttachmentKey dedup via an injected closure, stale
  penalty), confirm red, then move the real bodies (green). This adds direct presenter
  coverage AND proves the move. Same pattern as `BridgeMetadataMerging`.
- **liveAttachmentKey closure**: must be passed exactly as `monitoring.liveAttachmentKey(for:)`
  — a wrong/missing closure would change dedup. The Verify byte-diffs the delegate.
- **Do NOT move** the cached `sessionBuckets` accessor or the sectioning/closed-island
  derivations (out of scope; latter need char tests first).
- No human decision — scope settled (bucketing pipeline only; presenter = stateless
  enum per the scout's recommendation, since the pref sets don't overlap).
