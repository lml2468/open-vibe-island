---
type: Rule
title: Terminal jump resilience
description: The terminal jump / AX path must fail open (degrade to activation) on Automation denial, bound every subprocess with a timeout, and gate AX calls on trust — without swallowing genuine errors.
tags: ["jump", "fail-open", "ax", "timeout", "subprocess", "correctness"]
timestamp: 2026-07-08T11:52:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: terminal-jump-resilience
tier: repo
priority: 80
load_bearing: true
inject_when:
  paths:
    - "Sources/OpenIslandApp/TerminalJumpService.swift"
    - "Sources/OpenIslandApp/TerminalJumpTargetResolver.swift"
    - "Sources/OpenIslandApp/KeystrokeInjector.swift"
    - "Sources/OpenIslandApp/ForegroundTerminalSessionProbe.swift"
    - "Sources/OpenIslandApp/TerminalSessionAttachmentProbe.swift"
  touches: ["jump", "ax", "timeout", "fail-open"]
source: self
supersedes: []
---

# Terminal jump resilience

Terminal jump-back is the app's headline feature and runs against external apps
whose permission state and responsiveness the app does not control. The jump / AX
path must degrade gracefully, never hang, and never assume a permission it hasn't
checked.

## Fail open — but selectively

- An AppleScript step that fails because the user **declined the Automation
  (Apple Events) prompt** surfaces as `TerminalJumpError.appleScriptFailed`. Catch
  that specific case and fall through to the plain `open -b` activation fallback
  (`attemptAppleScriptJump`), so a denied user still gets the app brought forward.
- Do **not** blanket-`try?` the jumpers. Catch only the denial error; let any
  other error propagate. A blanket catch hides real bugs while looking like
  "fail-open". Every fail-open change must ship a paired test that a *genuinely
  unexpected* error still throws (the guard against catch-all swallowing).

## Bound every subprocess

- Any `Process` on the jump path (`open`, `osascript`, editor/tmux/zellij/wezterm
  CLIs) must run through a bounded wait — `runProcessWithTimeout`
  (`DispatchGroup.wait(timeout:)` → `terminate()` → brief reap), the same pattern
  the probes use. Never a bare `waitUntilExit()`: `Task.cancel()` cannot interrupt
  a blocking wait, so a hung child would block the caller forever and leak the
  process. On timeout, report failure so the jump falls through to its next
  fallback.

## Gate AX / permission-dependent calls

- Before driving another process via Accessibility (`click menu item`, synthetic
  events), check `AXIsProcessTrusted()` and return a `Bool` so the caller can skip
  wasted retries (e.g. `jumpToWarpPane`'s cycle loop) when the permission is
  absent. Make the trust source injectable so the gate is unit-testable without
  real TCC state.

## Out of scope of this rule (separate slices)

- The per-terminal strategy abstraction (no `TerminalJumper` protocol yet), the
  duplicated AppleScript probe cluster, `jumpToWarpPane`'s `Thread.sleep` loop
  body, and the hardcoded English Warp menu path are known and tracked separately
  — this rule governs resilience (denial/timeout/trust), not structure.
