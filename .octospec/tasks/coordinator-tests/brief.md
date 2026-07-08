---
type: Task
title: "Task: coordinator-tests"
description: Add unit coverage for the two untested coordinators and make the unwired-stateAccessor degradation explicit (logged + testable) instead of silent
tags: ["testability", "coordinator", "correctness", "session-discovery"]
timestamp: 2026-07-08T13:04:37Z
# --- octospec extension fields ---
slug: coordinator-tests
upstream: arch-quality-audit-r2 (discovery findings #4, #16)
source: self
revision: 1
approvals: []
---

# Task: coordinator-tests

> Fourth slice of the `arch-quality-audit-r2` discovery. Raises coverage on the
> two largest untested orchestration files and turns their silent
> unwired-accessor degradation into an explicit, testable signal. Independent
> branch off `origin/main` (three prior slices merged).

## Goal

1. **Make the unwired-`stateAccessor` fallback explicit (#16).** Both coordinators
   read state via `stateAccessor?() ?? SessionState()`
   (`SessionDiscoveryCoordinator.swift:75-81`, `ProcessMonitoringCoordinator.swift:99-102`):
   a nil accessor (a wiring bug / lifecycle race) silently substitutes an empty
   `SessionState`, indistinguishable from a genuinely empty world. Change the
   getter so that when the accessor is nil it (a) logs via `os.Logger.error` and
   (b) increments an internal counter (e.g. `unwiredStateAccessReads`) that a test
   can assert — while still returning `SessionState()` so **production behavior is
   unchanged** (the accessor is always wired in `AppModel`). This makes the
   contract observable without adding a public closure or a crash.
2. **Add unit coverage for the pure coordinator logic (#4).** Both files (~1,458 /
   ~558 LOC) have essentially no direct tests. Add focused unit tests for the
   deterministic, dependency-free logic, using a fake `stateAccessor` (already a
   settable closure) and the existing `AgentSession`/`SessionState` builders —
   **no** real timers/subprocess/filesystem. Targets:
   - `SessionDiscoveryCoordinator.mergeDiscoveredSessions(_:)` (`:187`) and the
     merge family it drives: `merge(discovered:into:)` (`:217`),
     `mergeAttachmentState` (`:296`), `mergeOpenCodeMetadata`/`mergeCursorMetadata`/
     `mergeCodexMetadata`/`mergeClaudeMetadata` (`:245/:268/:310/:333`),
     `existingSessionID(matchingTranscriptOf:in:)` (`:203`).
   - `ProcessMonitoringCoordinator` pure helpers: `supportedTerminalApp(for:)`
     (`:1363`), `liveAttachmentKey(for:)` (`:1237`), `normalizedPathForMatching`
     (`:1345`), `normalizedTTYForMatching` (`:1354`).

## Background

- Both coordinators are `@MainActor @Observable final class` with no custom init;
  dependencies are field-injected closures (`stateAccessor`, `stateUpdater`, …)
  set after construction, so a test does
  `let c = SessionDiscoveryCoordinator(); c.stateAccessor = { seededState }`. The
  heavy I/O collaborators (registries, discovery, probes) are hard-wired private
  `let`s — so this slice tests only the logic reachable **without** touching them.
- Precedent: `PerformancePolicyTests` already unit-tests
  `ProcessMonitoringCoordinator`'s static policy funcs via `@testable import`;
  `AppModelSessionListTests` establishes the `AgentSession`/`SessionState`/
  `JumpTarget` builder pattern to reuse.
- Logger precedent: `AppModel` and `WatchHTTPEndpoint` use
  `Logger(subsystem: "app.openisland", category: …)`; `os` is not yet imported in
  either coordinator — this slice adds it.
- **No indexed rule matches these files/tags** (verified) — this slice may promote
  a small `coordinator-wiring` rule at Finish for the explicit-degradation pattern.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionDiscoveryCoordinator.state` getter** (`:75-81`) and
  **`ProcessMonitoringCoordinator.state` getter** (`:99-102`) — the nil-swallow
  sites; behavior for a *wired* accessor must be unchanged. `[coordinator]`
- **`SessionDiscoveryCoordinator` merge family** (`:187-347`) — pure session-merge
  logic under test; outputs must be preserved (tests pin current behavior).
  `[coordinator] [session-discovery]`
- **`ProcessMonitoringCoordinator` pure matching helpers** (`:1237-1419`) — under
  test; outputs preserved. `[coordinator]`
- **`AppModel` wiring** (`AppModel.swift:654,689`) — sets both accessors; this
  slice must not change that the production accessor is always wired. `[coordinator]`

## Out of scope
- **Making the hard-wired I/O collaborators injectable** (registries, discovery,
  probes) — a larger refactor; this slice tests only what's reachable without them.
- **Testing timer/Task loops, filesystem, NSWorkspace, subprocess paths**
  (`startMonitoringIfNeeded`, `loadStartupDiscoveryPayload`, `schedule*Persistence`,
  `is*DesktopAppRunning`, the Cursor/Claude-Desktop branches of
  `sessionIDsWithAliveProcesses`) — explicitly not covered.
- **Any change to merge/matching behavior** — tests characterize current behavior;
  this is not a refactor of the logic itself.
- No change to public method signatures or the production result of a wired
  accessor.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — unwired `stateAccessor` is observable, not silent (both coordinators).**
  With `stateAccessor` left nil, reading state (directly or via a method that
  reads it) increments `unwiredStateAccessReads` (starts at 0) on each
  `SessionDiscoveryCoordinator` and `ProcessMonitoringCoordinator`, and still
  returns an empty `SessionState`. *(Testable: fails first — the counter does not
  exist / stays 0.)*
- **A2 — a wired `stateAccessor` never trips the counter and returns its state.**
  With `stateAccessor = { seeded }`, the read returns `seeded` and
  `unwiredStateAccessReads == 0`. *(Testable: preservation guard — production path
  unchanged.)*
- **A3 — `mergeDiscoveredSessions` characterization.** Given a seeded `state` and
  discovered sessions, the merge: (i) updates an existing session by id
  (newer-wins fields, attachment/metadata precedence, `isCodexAppSession` OR-ing),
  (ii) matches an existing session by transcript path when ids differ, and
  (iii) inserts a genuinely new session. *(Testable: asserts merged output; fails
  first because the suite doesn't exist.)*
- **A4 — merge-precedence helpers.** `mergeAttachmentState` yields the documented
  `attached > stale > detached` precedence; the per-agent metadata mergers
  (`codex`/`claude`/`openCode`/`cursor`) nil-coalesce discovered-over-existing and
  collapse `.isEmpty` to nil. *(Testable: exhaustive small cases; fails first.)*
- **A5 — `ProcessMonitoringCoordinator` pure helpers.**
  `supportedTerminalApp` maps known aliases to canonical names and returns nil for
  unknown/blank; `liveAttachmentKey` returns the expected key for each of its
  branches (Codex.app thread / sessionID / TTY / cwd+title / cwd / nil);
  `normalizedPathForMatching` / `normalizedTTYForMatching` normalize as documented
  (blank→nil, `/dev/` handling). *(Testable: table-driven; fails first.)*
- **A6 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
