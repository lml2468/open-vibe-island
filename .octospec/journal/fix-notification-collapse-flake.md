---
type: Journal
title: "Journal: fix-notification-collapse-flake"
description: Made the notification auto-collapse pointer check injectable so its tests are deterministic instead of depending on the real hardware cursor
tags: ["testability", "flake", "overlay", "ui", "correctness"]
timestamp: 2026-07-09T01:45:00Z
slug: fix-notification-collapse-flake
source: self
---

# Journal: fix-notification-collapse-flake

Follow-up slice fixing the flake surfaced during `coordinator-tests`.

## What was done

`OverlayUICoordinator` decided whether to schedule/defer the notification
auto-collapse by reading the **real hardware cursor** at three sites
(`overlayPanelController.isPointInExpandedArea(NSEvent.mouseLocation)` in
`updateNotificationAutoCollapse`, `shouldDeferTimedNotificationAutoCollapse`,
`isPointerInsideCurrentNotificationCard`). Since `notchOpen` creates a real
`NotchPanel`, a cursor sitting over the panel region made
`updateNotificationAutoCollapse` take the pointer-inside early-return and never
schedule the task — so `hasPendingNotificationAutoCollapse` was false when the
test expected true. Environment/order dependent → the flake.

Fix: the three reads now route through a private `isPointerInExpandedArea()` that
consults an injectable `pointerInExpandedAreaProvider: (() -> Bool)?` when set,
else the real panel + `NSEvent.mouseLocation` check. Tests set `{ false }`/`{ true }`
for determinism. Production behavior is unchanged (nil provider = today's check).

## Verification

- Reworked the previously-flaky `completionNotificationHoverCancelsPendingTimedCollapse`
  to inject `{ false }`, plus two new deterministic tests: schedules when pointer
  reported outside (A2), does not schedule when reported inside (A3).
- TDD trail: `red:` declared the provider but did NOT consult it at the call sites,
  so A3 (`{ true }` → must not schedule) failed for the right reason (real cursor
  still drove the decision); Green wired the helper. Green did not touch the tests
  (`git diff red..green -- Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS — reverted to red to confirm the failure
  reason, verified all 3 sites routed + exact nil-fallback + no retain cycle, and
  ran the cluster **5× green**. Gate green: `harness.sh ci` (416 tests) under
  warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **A "timing flake" is often a hidden-system-state flake.** The obvious suspect
  was the 10s auto-collapse timer; the actual cause was `NSEvent.mouseLocation` +
  a real panel in the schedule decision. Diagnosing it required tracing *what the
  decision reads*, not just *what delays it*. Before adding an injectable clock,
  check whether the nondeterminism is a clock at all — here it was the cursor.
- **Inject the system-state read, defaulting to the real read.** Mirrors the
  established `OverlayUICoordinator` accessor-closure pattern and the
  `coordinator-wiring` rule's "test through injected closures / prefer a seam over
  real system state" guidance — no production behavior change, no new public
  callback, and the previously-flaky assertion becomes deterministic. Kept the
  10s delay injection out of scope: no test waits for the timer, so it wasn't
  needed (adding an unused seam is churn).
