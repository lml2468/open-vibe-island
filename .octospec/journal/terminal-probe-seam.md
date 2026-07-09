---
type: Journal
title: "Journal: terminal-probe-seam"
description: Added injectable appleScriptRunner + appRunningChecker seams to the two terminal probe types, unlocking real unit tests for their AppleScript parse/availability logic
tags: ["testability", "applescript", "terminal", "seam"]
timestamp: 2026-07-09T05:55:00Z
slug: terminal-probe-seam
source: self
---

# Journal: terminal-probe-seam

Twelfth implemented slice of the `arch-quality-audit-r2` discovery — the enabler
for the remaining cluster-A dedup. First cluster-A slice with **real** tests
(the prior three were `N/A(test)` verbatim moves).

## What was done

`TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe` gained
`init(appleScriptRunner:appRunningChecker:)` with both closures **defaulted**
(mirroring `TerminalJumpService`); `runAppleScript`/`isRunning` now delegate to the
injected closures. The prior `Process`-based `runAppleScript` bodies moved verbatim
into `static defaultAppleScriptRunner(script:)` on each type (each keeping its own
NSError domain + timeout — 3 vs 1.0), used as the init default. No dedup — that's
the next slice, now trivially guarded by these tests.

## Verification

- New `TerminalProbeSeamTests` (5): appRunningChecker `{false}` short-circuits
  availability without calling the runner (A1); an injected FS(31)/RS(30) payload
  parses to the expected `GhosttyTerminalSnapshot`s / `TerminalTabSnapshot`s (A2,
  Ghostty + Terminal); a throwing runner → `.unavailable` (A3); the resolver seam
  constructs with fakes (A4).
- TDD trail: `red:` added the init params (compiles) but left `runAppleScript`/
  `isRunning` on the hardcoded impls, so the seam tests failed on assertion; Green
  flipped both delegates (`git diff red..green -- Tests/` = 0 bytes).
- Behavior-neutral (defaults reproduce the prior impls exactly): all 25 bare-`()`
  constructions untouched; existing `TerminalSessionAttachmentProbeTests` +
  `AppModelSessionListTests` pass unchanged.
- Independent Verify (fresh context) PASS, no findings. Gate green: `harness.sh ci`
  (439 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **The seam comes before the dedup — and is where the real tests live.** The
  three prior cluster-A cuts (normalize/snapshots/scripts) were all `N/A(test)`
  verbatim relocations because the AppleScript-driven logic was locked behind a
  real `Process`/`NSRunningApplication`. Adding the defaulted injection seam FIRST
  converts that logic into genuine failing-first tests (inject a canned
  separator-delimited payload, assert the parsed snapshots) and makes the
  subsequent `runAppleScript`/`isRunning` dedup a behavior-neutral move guarded by
  them. Sequencing: seam (real tests) → dedup (mechanical, guarded) beats trying
  to dedup untestable code.
- **A defaulted init param on a value type is a zero-breakage seam.** Adding
  `init(x: X = default)` to a struct that was only ever built with `()` keeps every
  existing construction (here 2 production + 23 test) compiling, so the seam lands
  with no call-site churn and production behavior identical — the default *is* the
  old code. Mirror an existing seam in the codebase (`TerminalJumpService`) for
  shape consistency.
- **Next slice (cluster A dedup):** move the two `defaultAppleScriptRunner` static
  impls into a shared `TerminalProbeSupport.defaultAppleScriptRunner(domain:timeout:)`
  (parameterized by the only two differences) + optionally a shared default
  running-checker — now a real behavior-neutral dedup guarded by these tests.
  Still deferred after that: `corrected*JumpTarget` (Ghostty variant differs —
  Probe Zellij guard) and the resolver's two inline non-throwing osascript blocks.
  See [[terminal-jump-resilience]].
