---
type: Journal
title: "Journal: dedup-terminal-snapshots"
description: Moved the byte-identical GhosttyTerminalSnapshot/TerminalTabSnapshot structs into shared top-level types, with typealias shims for external qualified references
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T05:20:00Z
slug: dedup-terminal-snapshots
source: self
---

# Journal: dedup-terminal-snapshots

Tenth implemented slice of the `arch-quality-audit-r2` discovery — the second cut
of finding #9 **cluster A**, building on the `TerminalProbeSupport` shared home.

## What was done

`GhosttyTerminalSnapshot` and `TerminalTabSnapshot` (byte-identical pure-data
structs) were nested in both `TerminalJumpTargetResolver` and
`TerminalSessionAttachmentProbe`. Moved them verbatim to shared top-level types in
`TerminalProbeSupport.swift` and deleted the four nested copies. The Resolver's
were internal-only (no shim). The Probe's nested names are referenced with the
qualified spelling `TerminalSessionAttachmentProbe.<Name>` by
`ProcessMonitoringCoordinator` + ~22 test sites, so it keeps `typealias` shims.

## Verification

- No new tests (r2 acceptance is `N/A(test)` — pure relocation, see Learning).
  Proof is A4: the ~40 existing references + the ~40-case
  `TerminalSessionAttachmentProbeTests` + `AppModelSessionListTests` compile and
  pass **unchanged**, and the moved struct bodies diff byte-identical to the
  deleted ones.
- Independent Verify (fresh context) PASS — confirmed the verbatim diff, the shim
  resolves without a cycle, and out-of-scope respected. Gate green: `harness.sh
  ci` (434 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **A pure verbatim type relocation can't have a valid failing-first test —
  reframe to `N/A(test)`, don't fake a Red.** A unit test referencing the moved
  top-level type fails to *compile* on the pre-move tree (octospec rejects a
  compile-error as an invalid Red), and a struct move has no wrong-value to
  assert. This surfaced mid-Implement under autopilot; the honest response was a
  spec-changing Iterate (r1→r2, N/A(test) with the reason, stop for re-approval),
  not an artificial wrong-value stub. Same discipline as `ui-decomposition`:
  behavior-neutrality is proven by a byte-identical diff + the callers' existing
  suites, and the acceptance must *say so* rather than pretend to be TDD.
- **`ModuleName.Type` breaks when a same-named type shadows the module.** The app
  has `struct OpenIslandApp: App` (the `@main` entry), so `OpenIslandApp.Foo`
  resolves to that struct, not the module — a nested `typealias Foo =
  OpenIslandApp.Foo` fails with "not a member type of struct OpenIslandApp". Fix:
  a **file-scope** alias (`typealias SharedFoo = Foo`, where at file scope `Foo`
  unambiguously means the top-level type since no nesting is in scope), then point
  the nested shim at `SharedFoo`. The file-scope aliases must be `internal` (not
  `private`) because the nested `internal` typealias's underlying type must be at
  least as visible.
- **Deferred cluster-A remainder** (order): AppleScript source-string constants →
  `runAppleScript`/`isRunning` (need an injection seam first) → `corrected*JumpTarget`
  last (Ghostty variant differs — Probe Zellij guard; needs Resolver flow tests).
  See [[terminal-jump-resilience]].
