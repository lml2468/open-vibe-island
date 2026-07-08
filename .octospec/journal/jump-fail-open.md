---
type: Journal
title: "Journal: jump-fail-open"
description: Terminal jump honors fail-open on Automation denial, bounds every subprocess with a timeout, and gates AX keystroke injection on trust
tags: ["correctness", "jump", "fail-open", "ax", "timeout", "subprocess"]
timestamp: 2026-07-08T11:52:00Z
slug: jump-fail-open
source: self
---

# Journal: jump-fail-open

Second implemented slice of the `arch-quality-audit-r2` discovery (findings #5,
#14). Independent branch off `origin/main` (no chain with the watch-auth PR).

## What was done

Three joined correctness fixes on the jump / AX path, all via the service's
existing injectable seams (`TerminalJumpService.swift`, `KeystrokeInjector.swift`).

1. **Fail-open on Automation denial (#5).** The AppleScript jumpers were called
   with bare `try`, so an `osascript` denial (`.appleScriptFailed`) unwound
   `jump(to:)` past the `open -b` activation fallbacks. New
   `attemptAppleScriptJump` catches **only** `.appleScriptFailed` → returns
   `false` → the caller falls through to activation; every other error still
   propagates. Applied at all six AppleScript call sites (3 main dispatch +
   3 tmux-path).
2. **Bounded subprocesses (#5).** New `runProcessWithTimeout` (DispatchGroup +
   `terminate()`, mirroring `TerminalSessionAttachmentProbe`'s precedent) caps
   `open`/`osascript`/CLI runners at 5s; a hung child is killed and the step
   reports failure instead of blocking forever + leaking a `Process`. All three
   `default*` runners route through it (no residual `waitUntilExit()`).
3. **AX-trust gate (#14).** `KeystrokeInjector` gained injectable
   `isProcessTrusted` (`AXIsProcessTrusted`) + `runScript` seams and now returns
   `Bool`; on untrusted it skips the keystroke and reports not-performed, so
   `jumpToWarpPane` bails out of its multi-second `tabCount+2` cycle loop instead
   of grinding through sleeps + SQLite reads against a permission it doesn't have.

## Verification

- New `JumpFailOpenTests` (8 XCTest): A1 denial→activation (iTerm/Ghostty/
  Terminal), A2 real error still propagates, A3 `runProcessWithTimeout` kills a
  real `/bin/sleep 5` under a 300ms budget + reports clean exit, A4 injection
  skipped when untrusted / proceeds when trusted.
- TDD trail: `red:` stubs (`runProcessWithTimeout`→`.completed(0)`; injector
  always runs; call sites still bare `try`) made the tests fail on assertions;
  Green did not touch the tests (`git diff red..green -- Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS, no findings. Gate green:
  `harness.sh ci` — 382 swift-testing + 32 XCTest, warnings-as-errors +
  `swiftlint --strict`, exit 0.

## Learning

- **Fail-open must be selective, not a blanket `try?`.** The correct fix catches
  the *specific* denial error (`.appleScriptFailed`) and degrades to activation,
  while letting genuinely unexpected errors propagate. A blanket `try?` would have
  satisfied "no hard error on denial" while silently hiding real bugs — so the
  brief pinned an explicit A2 test (an unexpected error must still throw) as the
  guard. When a slice's goal is "don't hard-fail," always add the paired "…but
  still surface real failures" test. Captured in the new `terminal-jump-resilience`
  rule.
- **Any `Process` + `waitUntilExit()` on the jump path is an unbounded hang.**
  Reuse the repo's `DispatchGroup.wait(timeout:)` → `terminate()` pattern
  (`runProcessWithTimeout`) rather than a bare wait; `Task.cancel()` cannot
  interrupt a blocking wait, so the deadline must live in the runner.
- **Gate a permission-dependent AX call with `AXIsProcessTrusted()` and return a
  Bool so the caller can skip wasted work.** The trust check is cheap; without it
  the caller burned seconds retrying a menu click that can never succeed. Make the
  trust source injectable so the gate is unit-testable without real TCC state.
- **`swift test` here is XCTest + swift-testing in one bundle** — the "382 tests"
  line is the swift-testing count; XCTest suites (`XCTestCase`) report separately
  ("Executed N tests"). Verify both ran, don't trust a single count.
