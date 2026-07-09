---
type: Task
title: "Task: fix-notification-collapse-flake"
description: Make the notification auto-collapse pointer check injectable so its tests are deterministic instead of depending on the real hardware cursor
tags: ["testability", "flake", "overlay", "ui", "correctness"]
timestamp: 2026-07-08T13:51:33Z
# --- octospec extension fields ---
slug: fix-notification-collapse-flake
upstream: arch-quality-audit-r2 (surfaced during coordinator-tests)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T01:36:33Z
---

# Task: fix-notification-collapse-flake

> Follow-up slice from the `coordinator-tests` slice, which surfaced a
> pre-existing order/timing flake. Makes the notification auto-collapse pointer
> check injectable so its tests are deterministic. Independent branch off
> `origin/main`.

## Goal

`completionNotificationHoverCancelsPendingTimedCollapse` (and its siblings) in
`AppModelSessionListTests` are flaky under the full suite. Root cause is **not**
the 10s timer: `OverlayUICoordinator` decides whether to schedule / defer the
auto-collapse by reading the **real hardware cursor** via
`overlayPanelController.isPointInExpandedArea(NSEvent.mouseLocation)` at three
sites (`OverlayUICoordinator.swift:392, :423, :433`). During `notchOpen` the
coordinator creates a real `NotchPanel`, so if the developer's/CI's cursor happens
to sit over the panel's screen region, `updateNotificationAutoCollapse` takes the
"pointer inside" early-return (`:392-395`) and never schedules the task — making
`hasPendingNotificationAutoCollapse` false when the test expects true. This is
environment/order dependent → the observed flake.

Fix: route those three cursor reads through a single injectable predicate
(`@ObservationIgnored var pointerInExpandedAreaProvider: (() -> Bool)?`),
defaulting (when nil) to the current
`overlayPanelController.isPointInExpandedArea(NSEvent.mouseLocation)`. Production
behavior is unchanged; tests set the provider to `{ false }` (pointer outside) or
`{ true }` (inside) to make the pending→cancel transition deterministic without
depending on the real cursor or a real timer.

## Background

- `OverlayUICoordinator` already uses the injectable-closure-with-default pattern
  (`activeIslandCardSessionAccessor`, `isSoundMutedAccessor`,
  `ignoresPointerExitAccessor`, all `@ObservationIgnored var …: (() -> …)?`,
  defaulted safely). The new seam mirrors this exactly.
- `AppModel` owns `let overlay = OverlayUICoordinator()` (`AppModel.swift:75`),
  reachable from tests via `@testable import` (existing tests already use
  `model.overlay.presentNotificationSurface(...)`), so a test can set
  `model.overlay.pointerInExpandedAreaProvider = { false }`.
- The three call sites: `updateNotificationAutoCollapse` (`:392`),
  `shouldDeferTimedNotificationAutoCollapse` (`:423`),
  `isPointerInsideCurrentNotificationCard` (`:433`). All three currently call
  `overlayPanelController.isPointInExpandedArea(NSEvent.mouseLocation)` directly.
- No existing test depends on the real 10s timer firing (verified by the scout:
  no test references the delay constant / task). So this change disturbs no
  timing-based assertion.
- **Injected rule:** `coordinator-wiring` matches `OverlayUICoordinator.swift`
  (touches: coordinator) — its "test pure logic through injected closures" and
  "prefer an injectable clock/seam over real timers/system state" guidance is
  exactly this fix.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`OverlayUICoordinator.updateNotificationAutoCollapse`** (`:382-419`) — decides
  whether to schedule the collapse task; the `:392` cursor early-return is the
  flake source. `[overlay] [coordinator]`
- **`OverlayUICoordinator.shouldDeferTimedNotificationAutoCollapse`** (`:421-424`)
  and **`isPointerInsideCurrentNotificationCard`** (`:431-434`) — the other two
  cursor reads. `[overlay]`
- **`hasPendingNotificationAutoCollapse`** (`:57-59`) and
  **`notePointerInsideIslandSurface`** (`:286-298`) — the observable the tests
  assert and the cancel path; behavior must be unchanged for a wired
  (production-default) provider. `[overlay]`
- **The flaky tests** in `AppModelSessionListTests.swift` (the notification-collapse
  cluster) — updated to inject the deterministic provider. `[flake]`

## Out of scope
- **Making the 10s delay injectable** — not needed for these tests (they assert
  the schedule/cancel transition, never wait for the timer). May be a later tidy;
  not this slice.
- **Refactoring `OverlayPanelController`** or the panel-creation path.
- **Any production behavior change** — the default provider must reproduce today's
  cursor check exactly.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — the collapse pointer check is injectable and defaults to the real check.**
  `OverlayUICoordinator` exposes `pointerInExpandedAreaProvider`; when unset,
  `updateNotificationAutoCollapse` / `shouldDeferTimedNotificationAutoCollapse` /
  `isPointerInsideCurrentNotificationCard` behave exactly as they do today
  (delegating to `overlayPanelController.isPointInExpandedArea(NSEvent.mouseLocation)`).
  *(Testable via A2/A3 behavior; the default path is preserved by construction.)*
- **A2 — with the pointer reported OUTSIDE, opening a notification schedules the
  collapse and hover cancels it — deterministically.** With
  `pointerInExpandedAreaProvider = { false }`: `notchOpen(reason: .notification, …)`
  makes `hasPendingNotificationAutoCollapse == true`, and
  `notePointerInsideIslandSurface()` makes it `false`. Run reliably (no dependence
  on real cursor). *(Testable: this is the previously-flaky assertion, now
  deterministic. Fails first — the provider seam doesn't exist.)*
- **A3 — with the pointer reported INSIDE, the collapse is not scheduled.** With
  `pointerInExpandedAreaProvider = { true }`, `notchOpen(reason: .notification, …)`
  leaves `hasPendingNotificationAutoCollapse == false` (the inside-pointer
  early-return). *(Testable: pins the deferral branch deterministically. Fails
  first — no seam.)*
- **A4 — gate is green, and the previously-flaky test is deterministic.**
  `swift build` + `swift test` pass under the repo gate; the notification-collapse
  tests use the injected provider (no reliance on `NSEvent.mouseLocation`).
  *(N/A(test): the gate itself; determinism is provided by construction, not a
  flaky repeat-run assertion.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
