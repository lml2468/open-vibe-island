---
type: Journal
title: "Journal: coordinator-tests"
description: Added unit coverage for the two untested coordinators' pure logic and made the unwired-stateAccessor degradation explicit (logged + testable counter)
tags: ["testability", "coordinator", "correctness", "session-discovery"]
timestamp: 2026-07-08T13:25:00Z
slug: coordinator-tests
source: self
---

# Journal: coordinator-tests

Fourth implemented slice of the `arch-quality-audit-r2` discovery (findings #4,
#16). Independent branch off `origin/main`.

## What was done

1. **Explicit unwired-`stateAccessor` signal (#16).** Both coordinators
   (`ProcessMonitoringCoordinator`, `SessionDiscoveryCoordinator`) read state via a
   private `state` computed property that used `stateAccessor?() ?? SessionState()`
   — a nil accessor silently degraded to an empty world. The getter now, on nil,
   increments a `private(set) var unwiredStateAccessReads` counter and logs via
   `os.Logger.error`, still returning `SessionState()`. Production behavior is
   unchanged (AppModel always wires the accessor); the counter makes the wiring
   contract observable and testable.
2. **Coverage for the pure logic (#4).** New `CoordinatorTestsSuite` (12 tests)
   for the previously-untested deterministic logic, driven with a fake
   `stateAccessor` and the existing `AgentSession`/`SessionState` builders — no
   timers/subprocess/filesystem: `SessionDiscoveryCoordinator.mergeDiscoveredSessions`
   (update-by-id newer-wins, transcript-path match, insert-new, attachment
   precedence, `isCodexAppSession` OR-ing) and `ProcessMonitoringCoordinator`
   helpers (`supportedTerminalApp`, `liveAttachmentKey` branches,
   `normalizedPath/TTYForMatching`).

## Verification

- `CoordinatorTestsSuite` (12 `@Test`, `@MainActor`): A1 counter trips on nil
  accessor (both coordinators), A2 wired accessor never trips + returns its state,
  A3–A5 characterize the merge family + matching helpers.
- TDD trail: `red:` added the counter as a stub (property present, never
  incremented) so A1 failed on assertion; A2–A5 are characterization tests that
  passed at red (proving the logic is reachable and correctly pinned). Green did
  not touch the tests (`git diff red..green -- Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS, no findings. Gate green:
  `harness.sh ci` — 411 tests / 50 suites, warnings-as-errors + `swiftlint
  --strict`, exit 0.

## Learning

- **A coverage slice's Red is legitimately "A1 fails, the rest characterize".**
  Most tests here pin *existing* behavior (they pass the moment they compile), so
  they can't "fail first" on a missing behavior — that's expected and honest for
  coverage work. The discipline is: the one genuine behavior change (#16) has a
  true failing-first test (the stubbed counter), and the characterization tests
  are proven reachable/non-vacuous (assert specific survivors, not just counts).
  Don't fake a Red for characterization tests by temporarily breaking the code.
- **A pre-existing timing flake surfaces when you change suite composition.**
  `completionNotificationHoverCancelsPendingTimedCollapse` (a real-timer AppModel
  test, untouched by this diff) failed once under the full harness, then passed on
  the base, in isolation, and on repeated full runs. Adding tests reshuffled
  suite timing enough to expose it. Diagnosis that saved a false "my change broke
  it": run the suspect test on the *base* tree and in isolation, and re-run the
  full suite for determinism — attribute by reproduction, not by coincidence.
  (That real-timer test is a candidate for an injectable-clock fix in a later
  slice.)
- **Make a silent fallback observable with a counter + log, not a crash.** For an
  invariant that "can't happen in production" (the accessor is always wired), an
  `assertionFailure` isn't unit-testable and a new public callback is overkill; a
  `private(set)` counter + `Logger.error` is the minimal testable seam. Captured
  as the `coordinator-wiring` rule.
