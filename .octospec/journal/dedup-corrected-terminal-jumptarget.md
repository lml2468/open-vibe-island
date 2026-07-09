---
type: Journal
title: "Journal: dedup-corrected-terminal-jumptarget"
description: Deduped the byte-identical correctedTerminalJumpTarget + nonEmptyValue into shared TerminalProbeSupport; deferred the diverging Ghostty variant
tags: ["dedup", "terminal", "jump", "maintainability"]
timestamp: 2026-07-09T06:45:00Z
slug: dedup-corrected-terminal-jumptarget
source: self
---

# Journal: dedup-corrected-terminal-jumptarget

Fourteenth implemented slice of the `arch-quality-audit-r2` discovery — the last
*clean* cluster-A dedup.

## What was done

`correctedTerminalJumpTarget(for:snapshot:)` (byte-identical in
`TerminalJumpTargetResolver` + `TerminalSessionAttachmentProbe`) and its helper
`nonEmptyValue(_:)` (also byte-identical, 24 refs each) were extracted into
`TerminalProbeSupport` statics. Both files' methods are now one-line delegates;
`nonEmptyValue`'s per-file private copy stays as a thin delegate so its ~23 call
sites each are untouched. Because the extracted method is a non-private static, it
gained a **real** direct unit test.

The diverging `correctedGhosttyJumpTarget` (the Probe has a `zellij` early-return
guard the Resolver lacks) was **deliberately left untouched** — deduping it is a
behavioral decision, not a dedup.

## Verification

- New `TerminalProbeCorrectedTargetTests` (4): applies the three Terminal
  corrections (app/tty/paneTitle); returns nil when already-correct and when the
  session has no jumpTarget; `nonEmptyValue` trims + nils empties.
- TDD trail: `red:` stubbed both statics to `nil`, so A1 (corrects) + A3
  (nonEmptyValue) failed on assertion while A2's nil-cases passed as preservation
  guards; Green filled the impls + delegates (`git diff red..green -- Tests/` = 0
  bytes).
- Behavior-neutral: shared impls byte-equivalent to the removed bodies (verified
  vs `origin/main`); the Terminal-correction body + trim now live in one place;
  existing `TerminalSessionAttachmentProbeTests` + `AppModelSessionListTests` pass
  unchanged.
- Independent Verify (fresh context) PASS, no findings — including confirmation
  that `correctedGhosttyJumpTarget` + the Zellij guard are unchanged. Gate green:
  `harness.sh ci` (446 tests) under warnings-as-errors + `swiftlint --strict`,
  exit 0.

## Learning

- **When two "duplicates" diverge, dedup the identical one and split off the
  difference — don't force it.** `correctedTerminalJumpTarget` was byte-identical
  (clean move); `correctedGhosttyJumpTarget` differed by a Zellij guard. Deduping
  the Ghostty pair would have either changed Resolver behavior (apply the guard
  where it isn't today) or baked an `applyZellijGuard: Bool` flag into the shared
  API — both smuggle a semantic decision into a "dedup" commit. The right call is
  to ship the identical half now and leave the divergent half as its own
  behavioral slice (prove the guard is unreachable in the Resolver, or accept it
  as an intentional change). A dedup PR must stay behavior-neutral.
- **Lift a shared helper's dependency alongside it, keeping per-file delegates.**
  The extracted method needed `nonEmptyValue`; lifting it to the shared home (with
  each file's copy reduced to a one-line delegate) keeps all 23 call sites per file
  compiling untouched and unblocks the future Ghostty slice, which also uses it.
- **Cluster-A status:** normalize + snapshots + scripts + seam + runAppleScript +
  this correctedTerminal dedup are done. **Remaining:** only
  `correctedGhosttyJumpTarget` (the Zellij-guard behavioral decision — now
  unblocked since the seam makes the Resolver testable) and the resolver's two
  inline non-throwing osascript blocks. See [[terminal-jump-resilience]].
