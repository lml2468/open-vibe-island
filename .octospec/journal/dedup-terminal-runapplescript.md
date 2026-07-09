---
type: Journal
title: "Journal: dedup-terminal-runapplescript"
description: Deduped the two byte-identical defaultAppleScriptRunner impls into a shared, tested TerminalProbeSupport.runOSAScript parameterized by timeout + error domain
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T06:10:00Z
slug: dedup-terminal-runapplescript
source: self
---

# Journal: dedup-terminal-runapplescript

Thirteenth implemented slice of the `arch-quality-audit-r2` discovery — the payoff
of `terminal-probe-seam`. Cluster A's biggest single dedup, and (thanks to the
seam) a **real** test-backed one rather than a verbatim `N/A(test)` move.

## What was done

`TerminalJumpTargetResolver.defaultAppleScriptRunner` and
`TerminalSessionAttachmentProbe.defaultAppleScriptRunner` were byte-identical
`Process` + `osascript` + `DispatchGroup`-timeout impls except two values (timeout
3 vs 1.0, NSError domain). Extracted the common impl into
`TerminalProbeSupport.runOSAScript(_:timeout:errorDomain:)`; each default is now a
one-line delegate passing its own timeout + domain. The runner's `Process` body
exists in exactly one place; behavior is unchanged (each type keeps its distinct
timeout/domain). The resolver's two inline non-throwing osascript blocks are a
different shape and stay out of scope.

## Verification

- New `TerminalProbeRunOSAScriptTests` (3, real osascript): a trivial script
  returns its trimmed output; a `delay 5` with a 0.3s timeout throws
  `NSError(domain: errorDomain, code: 408)` **and returns in ~0.3s** (asserted
  `elapsed < 3.0` — proves the terminate path, not a full-sleep block); an invalid
  script throws with the passed domain + nonzero code.
- TDD trail: `red:` stubbed `runOSAScript` to return `""`, so all three failed on
  assertion; Green filled the impl + both delegates (`git diff red..green --
  Tests/` = 0 bytes).
- Behavior-neutral: the shared impl is byte-equivalent to the removed bodies
  (verified vs `origin/main`, timeout/domain substituted); the prior slice's
  `TerminalProbeSeamTests` + `TerminalSessionAttachmentProbeTests` pass unchanged.
- Independent Verify (fresh context) PASS, no findings. Gate green: `harness.sh ci`
  (442 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Seam-then-dedup pays off: the dedup got a real timeout test the earlier moves
  couldn't.** The three prior cluster-A cuts were `N/A(test)` verbatim relocations
  because the code was untestable; `terminal-probe-seam` added the injection point,
  and this slice's shared `runOSAScript` is directly exercised by a real
  short-`osascript` test — including the fast-return timeout assertion that pins
  the deduped `DispatchGroup.wait → terminate` logic. Extracting behind a seam
  first turns "trust the diff" into "prove it with a test."
- **Parameterize only the differences.** The two impls differed by exactly two
  values (timeout, errorDomain); the shared helper takes exactly those two params
  and nothing else, so the delegates are trivial and the byte-equivalence is
  obvious. Resist widening the shared signature beyond the actual divergence.
- **Cluster-A status:** normalize + snapshots + scripts (verbatim) + seam + this
  runAppleScript dedup are done. Remaining: `isRunning` default is already a shared
  one-liner (not worth its own helper); `corrected*JumpTarget` is the last real
  piece (Ghostty variant differs — Probe Zellij guard; needs Resolver flow tests),
  and the resolver's two inline non-throwing osascript blocks. See
  [[terminal-jump-resilience]].
