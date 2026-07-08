---
type: Rule
title: Coordinator wiring
description: AppModel coordinators must not silently degrade on an unwired stateAccessor — surface it with a testable counter + log — and their pure logic must be unit-tested through injected closures.
tags: ["coordinator", "testability", "correctness", "session-discovery"]
timestamp: 2026-07-08T13:25:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: coordinator-wiring
tier: repo
priority: 75
load_bearing: false
inject_when:
  paths:
    - "Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift"
    - "Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift"
    - "Sources/OpenIslandApp/OverlayUICoordinator.swift"
    - "Sources/OpenIslandApp/HookInstallationCoordinator.swift"
  touches: ["coordinator"]
source: self
supersedes: []
---

# Coordinator wiring

`AppModel`'s coordinators are `@MainActor @Observable` classes whose dependencies
are field-injected closures (`stateAccessor`, `stateUpdater`, `on*` hooks) set
after construction. That shape is good for testing — but it has two traps.

## Don't silently degrade on an unwired closure

- A `stateAccessor?() ?? SessionState()` fallback makes a wiring bug (nil
  accessor) indistinguishable from a genuinely empty world. When a dependency
  closure is nil at a point it is required, **make it observable**: increment a
  `private(set)` counter (e.g. `unwiredStateAccessReads`) and `Logger.error`,
  then continue with the safe fallback. Do not add a public callback (overkill)
  or `assertionFailure` (not unit-testable, and crashes a shipping build).
- The fallback value itself stays (production always wires the closure, so the
  counter stays 0 there) — this is defense-in-depth + testability, not a behavior
  change.

## Unit-test the pure logic through the injected closures

- Set `stateAccessor = { seededState }` and call the coordinator's pure methods
  directly (merge/matching/normalization). Use the shared `SessionState(sessions:)`
  / `AgentSession` / `JumpTarget` builders. Do NOT drag in the hard-wired I/O
  collaborators (registries, discovery, probes) — those aren't injectable, so
  test only what's reachable without them, and leave timer/Task/filesystem/
  NSWorkspace paths out of unit scope.
- Characterization tests that pin existing behavior are legitimate coverage even
  though they pass on first compile (no "failing first"). Keep them non-vacuous:
  assert specific survivors/keys, not just counts.

## Watch real-timer tests when adding to a suite

- Adding tests reshuffles suite timing and can expose a pre-existing
  order/timing-dependent flake in an unrelated real-timer test. Before blaming
  your diff, reproduce on the base tree and in isolation; attribute by
  reproduction. Prefer an injectable clock over `Date.now`/real timers in any new
  coordinator logic so it doesn't add to that class of flake.
