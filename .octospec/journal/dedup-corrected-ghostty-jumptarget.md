---
type: Journal
title: "Journal: dedup-corrected-ghostty-jumptarget"
description: Deduped correctedGhosttyJumpTarget (incl. the Zellij guard) into shared TerminalProbeSupport — behavior-neutral by a reachability proof (guard dead in resolver, live in probe)
tags: ["dedup", "terminal", "jump", "correctness"]
timestamp: 2026-07-09T07:00:00Z
slug: dedup-corrected-ghostty-jumptarget
source: self
---

# Journal: dedup-corrected-ghostty-jumptarget

Fifteenth implemented slice of the `arch-quality-audit-r2` discovery — the last
real cluster-A dedup, resolving the one divergence (`correctedTerminalJumpTarget`'s
sibling) that the earlier slice deliberately deferred.

## What was done

`correctedGhosttyJumpTarget` was duplicated between the two probe types, differing
by exactly one 7-line Zellij early-return guard (present in the Probe, absent in
the Resolver). Extracted ONE shared `TerminalProbeSupport.correctedGhosttyJumpTarget`
**including the guard**, both callers delegate. No `applyZellijGuard` flag — a
reachability analysis proved the guard is inert in the Resolver, so merging it is
behavior-neutral for both callers. The Probe-only `correctedITermJumpTarget` is a
different method and stays untouched.

## Verification

- New `TerminalProbeCorrectedGhosttyTests` (3): corrects a stale target;
  synthesizes from the snapshot when the session has none; the Zellij guard returns
  nil (both "zellij"/"Zellij").
- TDD trail: `red:` stubbed the shared static to nil (A1/A3 fail on assertion, A2
  zellij→nil passes as a guard); Green filled the impl + both delegates
  (`git diff red..green -- Tests/` = 0 bytes).
- Byte-equivalence: shared body ≡ the Probe's removed body (with guard); = the
  Resolver's removed body + the 7-line guard only (verified vs `origin/main`).
- **Independent Verify re-derived the reachability proof** (not on faith):
  Resolver filter (`:91-94`) + nil-path seed exclude/never-produce zellij →
  guard dead; Probe `ambiguousSessions` (`:169`) admits zellij → guard live.
  Existing `TerminalSessionAttachmentProbeTests` + `AppModelSessionListTests` pass
  unchanged. Gate green: `harness.sh ci` (449 tests), exit 0.

## Learning

- **A dedup can be behavior-neutral despite a divergence — if the divergent code is
  provably dead in one caller.** Two "duplicates" differing by a guard don't force a
  flag or a behavior change: here the Zellij guard is unreachable in the Resolver
  (its candidate filter excludes zellij sessions and its nil-path seeds
  `terminalApp="Ghostty"`) and needed in the Probe (its ambiguous-session catch-all
  admits zellij). Merging *with* the guard preserves both callers' observable
  behavior. The `applyZellijGuard: Bool` flag would have been complexity guarding a
  scenario static analysis proves can't occur.
- **When neutrality rests on a reachability argument, make the reviewer re-derive
  it — a test can't.** No unit/flow test can isolate "the guard doesn't affect the
  Resolver," because the Resolver's entry filter already excludes zellij, so any
  test outcome is attributable to the filter, not the guard. The honest artifact is
  the static trace (entry filter + seed), and Verify's job is to independently
  reproduce it, which it did. Flag this limitation in the brief up front rather
  than pretend a test proves it.
- **Cluster A is now essentially complete** (normalize, snapshots, scripts, seam,
  runAppleScript, correctedTerminal, correctedGhostty). The only remainder is the
  resolver's two inline non-throwing osascript blocks (a different shape — return
  nil, not throw; low value, may not be worth a slice). See
  [[terminal-jump-resilience]].
