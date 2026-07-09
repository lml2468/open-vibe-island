---
type: Task
title: "Task: dedup-terminal-runapplescript"
description: Dedup the two byte-identical defaultAppleScriptRunner impls into a shared TerminalProbeSupport.runOSAScript, parameterized by timeout + error domain
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T05:58:41Z
# --- octospec extension fields ---
slug: dedup-terminal-runapplescript
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A)
source: self
revision: 1
approvals: []
---

# Task: dedup-terminal-runapplescript

> Thirteenth slice of the `arch-quality-audit-r2` discovery — the payoff of the
> `terminal-probe-seam` slice: now that the AppleScript runner is behind an
> injected seam (with tests), dedup its two identical default impls. Independent
> branch off `origin/main`.

## Goal

`TerminalJumpTargetResolver.defaultAppleScriptRunner(script:)`
(`TerminalJumpTargetResolver.swift:769-802`) and
`TerminalSessionAttachmentProbe.defaultAppleScriptRunner(script:)`
(`TerminalSessionAttachmentProbe.swift:1293-1330`) are byte-identical `Process` +
`osascript` + `DispatchGroup`-timeout implementations **except** two values: the
timeout (`Self.appleScriptTimeout` = 3 vs 1.0) and the NSError `domain`
(`"TerminalJumpTargetResolver"` vs `"TerminalSessionAttachmentProbe"`).

Extract one shared `TerminalProbeSupport.runOSAScript(_:timeout:errorDomain:)
throws -> String` holding the common impl, and reduce each type's
`defaultAppleScriptRunner` to a one-line delegate passing its own timeout +
domain. Behavior is unchanged (each type keeps its distinct timeout/domain); this
consolidates ~35 lines of `Process`/timeout code into one place.

## Background

- This is the follow-up teed up by `terminal-probe-seam`: `runAppleScript` on both
  types already delegates to the injected `appleScriptRunner`, whose default is
  the per-type `defaultAppleScriptRunner`. This slice only touches those two
  static defaults — the seam, the instance methods, and all call sites are
  untouched.
- **Now genuinely testable** (unlike the earlier `N/A(test)` cluster-A moves): the
  shared `runOSAScript` runs a real `osascript`, so it has real behavioral tests —
  a trivial script returns its output; a script that sleeps past a tiny injected
  timeout throws the timeout error with the passed `errorDomain`. (Mirrors the
  `perf-tmux-memoize` / jump-fail-open timeout-test style with a real short
  subprocess.)
- The two **inline osascript blocks** in the resolver (`~:357-400,~:605-648`) are a
  DIFFERENT shape (return-nil, not throwing) and are **out of scope** — do not fold
  them in.
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump)
  — the runner's bounded-timeout + throwing behavior must be preserved exactly.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`TerminalJumpTargetResolver.defaultAppleScriptRunner`** (`:769`) and
  **`TerminalSessionAttachmentProbe.defaultAppleScriptRunner`** (`:1293`) — become
  one-line delegates to the shared helper. `[applescript] [terminal]`
- **New `TerminalProbeSupport.runOSAScript(_:timeout:errorDomain:)`** — the shared
  impl; its timeout/throw/output behavior defines correctness (must match the
  removed bodies exactly). `[applescript]`
- **Per-type `appleScriptTimeout` (3 / 1.0) + NSError domains** — preserved by
  each delegate passing its own values; production behavior unchanged. `[applescript]`
- **The injected-seam defaults + existing seam tests** (`TerminalProbeSeamTests`) —
  still pass (the default still produces the same runner). `[terminal]`

## Out of scope
- **The two inline non-throwing osascript blocks** in the resolver — separate
  shape, separate (or no) slice.
- **`isRunning`/`appRunningChecker` dedup** — its default is a one-liner already
  shared in spirit; not worth a separate helper here (leave the per-type default
  closures as-is).
- **`corrected*JumpTarget`** (Ghostty variant differs — Probe Zellij guard).
- No change to the seam API, timeout values, NSError domains/codes, or AppleScript
  text.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `runOSAScript` returns a trivial script's output.**
  `TerminalProbeSupport.runOSAScript("return \"open-island\"", timeout: 5,
  errorDomain: "T")` returns `"open-island"` (trimmed). *(Testable: real short
  osascript. Fails first — the helper does not exist.)*
- **A2 — `runOSAScript` throws with the given domain on timeout.** A script that
  sleeps well past a tiny timeout (e.g. `delay 5` with `timeout: 0.3`) throws an
  `NSError` whose `domain` == the passed `errorDomain` and `code` == 408, and
  returns within a small bound (does not block for the full sleep). *(Testable:
  real sleep + short timeout; assert thrown domain/code + elapsed < ~3s. Fails
  first.)*
- **A3 — both defaults delegate to the shared helper with their own timeout +
  domain.** `TerminalJumpTargetResolver.defaultAppleScriptRunner` and
  `TerminalSessionAttachmentProbe.defaultAppleScriptRunner` are one-line delegates
  to `TerminalProbeSupport.runOSAScript`, and the inline `Process` body exists in
  exactly one place. *(Verifiable: grep — `Process()` for the runner appears once
  (in TerminalProbeSupport); each default is a delegate. The distinct domains/
  timeouts are passed through.)*
- **A4 — behavior neutral + gate green.** The existing `TerminalProbeSeamTests`,
  `TerminalSessionAttachmentProbeTests`, and `AppModelSessionListTests` pass
  unchanged; `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
