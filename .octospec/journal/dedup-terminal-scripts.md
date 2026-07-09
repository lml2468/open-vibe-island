---
type: Journal
title: "Journal: dedup-terminal-scripts"
description: Extracted the byte-identical Ghostty/Terminal AppleScript source-string literals into shared constants; parse wrappers stay per-file
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T05:40:00Z
slug: dedup-terminal-scripts
source: self
---

# Journal: dedup-terminal-scripts

Eleventh implemented slice of the `arch-quality-audit-r2` discovery — the third
cut of finding #9 **cluster A**, into the `TerminalProbeSupport` shared home.

## What was done

The Ghostty and Terminal.app enumeration AppleScript source strings were
byte-identical inline literals in all four `let script = """…"""` sites across
`TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe`. Moved them into
two `static let` constants (`ghosttyEnumerationScript`, `terminalEnumerationScript`)
on `TerminalProbeSupport`; the four sites now reference the constants. The per-file
parse wrappers (Resolver `try?`→optional, Probe `try`→throwing), the Swift
separator constants (`\u{1F}` vs `\u{1f}` — cosmetic, belong to the wrappers), and
the Probe-only iTerm script are all unchanged.

## Verification

- No new tests (r1 acceptance is `N/A(test)` — verbatim literal relocation, framed
  up front this time from the `dedup-terminal-snapshots` r2 lesson).
- Byte-identity proven: extracted the base literals + new constants, stripped Swift
  multiline indentation, diffed — Ghostty (912 bytes) and Terminal (801 bytes)
  identical; base resolver == base probe, so one shared constant is correct for
  both. The ~40-case `TerminalSessionAttachmentProbeTests` (which parse the script
  output) + `AppModelSessionListTests` pass unchanged.
- Independent Verify (fresh context) PASS — reproduced the runtime-content diff and
  confirmed wrappers/iTerm untouched. Gate green: `harness.sh ci` (434 tests) under
  warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Swift multiline-literal indentation strips to the closing `"""` column — so
  "byte-identical" must be checked on the *runtime* string, not the source.** The
  old literals were 8-space-indented (closing `"""` at 8), the new constant
  4-space-indented (closing at 4); both strip to 0-indent content, so the runtime
  strings match. Prove it by extracting both, removing each's source indent, and
  diffing — never eyeball indentation-sensitive relocations.
- **Move only the duplicated literal; leave the diverging wrappers.** The scripts
  were identical but the two callers parse them differently (optional vs throwing),
  so the shareable unit is the string constant, not the fetch method. Extracting
  the narrow common piece keeps the diff behavior-neutral and small.
- **N/A(test) framed at r1 — no iterate needed.** Unlike `dedup-terminal-snapshots`
  (which discovered the pure-relocation-has-no-valid-Red problem mid-Implement and
  had to iterate r1→r2), this brief marked the acceptance `N/A(test)` from the
  start. Recognizing "this is a verbatim relocation" at Plan time avoids the
  wasted approve→implement→iterate→re-approve cycle.
- **Deferred cluster-A remainder:** `runAppleScript`/`isRunning` (need an injection
  seam before they're safely testable) → `corrected*JumpTarget` last (Ghostty
  variant differs — Probe Zellij guard; needs Resolver flow tests). See
  [[terminal-jump-resilience]].
