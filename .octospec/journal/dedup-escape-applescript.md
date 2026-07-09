---
type: Journal
title: "Journal: dedup-escape-applescript"
description: Extracted the 2 identical escapeAppleScript copies into one shared, unit-tested AppleScriptEscaping helper
tags: ["dedup", "applescript", "jump", "maintainability", "security"]
timestamp: 2026-07-09T03:00:00Z
slug: dedup-escape-applescript
source: self
---

# Journal: dedup-escape-applescript

Eighth implemented slice of the `arch-quality-audit-r2` discovery — the second
small piece of finding #9 cluster C (after `dedup-shellquote`). Behavior-neutral.

## What was done

`TerminalJumpService` (instance `escapeAppleScript`, 7 call sites) and
`TerminalTextSender` (static `escapeAppleScript`, 4 call sites) each carried an
identical AppleScript double-quote-string escaper (nil→"", `\`→`\\`, `"`→`\"`).
Extracted into one `AppleScriptEscaping.escape(_:)` in a new
`Sources/OpenIslandApp/AppleScriptEscaping.swift`, deleted both copies, and routed
all 11 call sites through it — normalizing the instance-vs-static shape mismatch to
a single `static func`. The escaping — previously untested — now has a dedicated
`AppleScriptEscapingTests`.

## Verification

- New `AppleScriptEscapingTests` (5): nil→"", plain pass-through, backslash, double
  quote, and backslash-before-quote ordering.
- TDD trail: `red:` committed the stub (`escape` returns input unchanged) + the 11
  call-site swaps + both copy deletions, so the tests compiled and the escaping
  cases failed on assertion; Green swapped the body to the real escaping
  (`git diff red..green -- Tests/` = 0 bytes).
- Behavior-neutral proof: the existing jump/send suites still pass — the built
  AppleScript fragments are byte-identical.
- Not conflated with `escapeJSONStringContents` (a different, already-tested
  escaper) — confirmed untouched by the independent reviewer.
- Independent Verify (fresh context) PASS, no findings. Gate green: `harness.sh ci`
  (429 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **The ordering in a two-step escaper is load-bearing — pin it with a test.**
  Backslash must be escaped before the double quote; reversing it would re-mangle
  the `\` introduced by quote-escaping. The `\"` → `\\\"` case is the one that
  would catch a future "cleanup" that swaps the two `replacingOccurrences` calls.
  A byte-identical extraction is only safe if a test locks the order, not just the
  individual substitutions.
- **Second verse, same as the first (dedup cluster C).** Mirrors `dedup-shellquote`:
  extract a pure escaper into a shared helper, prove correctness with a new unit
  test and behavior-neutrality with the callers' existing tests. Two of the three
  cluster-C string helpers are now shared; the larger clusters (A: AppleScript
  script bodies; B: installer base) remain their own slices. See
  [[terminal-jump-resilience]] — the jump path's escaping is behavior-preserving
  here.
