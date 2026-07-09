---
type: Journal
title: "Journal: dedup-terminal-normalize"
description: Extracted the duplicated normalizedTerminalName into a shared TerminalProbeSupport helper — the first, safe cut of the AppleScript probe cluster
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T04:40:00Z
slug: dedup-terminal-normalize
source: self
---

# Journal: dedup-terminal-normalize

Ninth implemented slice of the `arch-quality-audit-r2` discovery — the first,
lowest-risk cut of finding #9 **cluster A** (the Terminal AppleScript probe
duplication between `TerminalJumpTargetResolver` and
`TerminalSessionAttachmentProbe`).

## What was done

`normalizedTerminalName(for:)` was a byte-identical private method in both files
(`value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()`, differing
only in line-wrapping). Extracted into `TerminalProbeSupport.normalizedTerminalName`
in a new `Sources/OpenIslandApp/TerminalProbeSupport.swift`, and reduced both
private methods to one-line forwarders — so all 15 call sites (8 Resolver +
7 Probe) stayed untouched. The normalization — previously untested, and
`TerminalJumpTargetResolver` had no test file at all — now has a dedicated
`TerminalProbeSupportTests`.

## Verification

- New `TerminalProbeSupportTests` (5): nil→nil, lowercase, trim+lowercase,
  whitespace-only→"", idempotent.
- TDD trail: `red:` committed the stub (`normalizedTerminalName` returns input) +
  both forwarders, so it compiled and the trim/lowercase cases failed on assertion
  (the forwarding also made the stub live in production); Green swapped the body
  (`git diff red..green -- Tests/` = 0 bytes).
- Behavior-neutral proof: the existing `TerminalSessionAttachmentProbeTests`
  (~21 cases) pass unchanged.
- Independent Verify (fresh context) PASS, no findings. Gate green: `harness.sh ci`
  (434 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Start a large dedup cluster with the one pure, testable piece — it also
  establishes the shared-home file.** Cluster A's tempting big wins
  (`runAppleScript`, the AppleScript source strings, snapshot structs) are all
  blocked or weakened by the two probe types having **no injection seam**
  (Process/osascript/`NSRunningApplication` can't be unit-tested here) — and
  `correctedGhosttyJumpTarget` isn't even identical (the Probe has a Zellij guard).
  Taking `normalizedTerminalName` first is small but creates `TerminalProbeSupport`,
  so later cluster-A slices are additive moves into an existing home rather than
  fresh files. Sequencing a risky cluster by "safest + foundational first" beats
  going after the biggest LOC win.
- **Forwarders make a shared-helper extraction provably neutral with minimal
  churn.** Leaving the two private methods as one-line delegates means the diff is
  two bodies + one new file, and every caller is untouched — the behavior-neutral
  claim reduces to "the helper equals the old body," which a unit test pins
  directly. See [[terminal-jump-resilience]].
- **Deferred cluster-A slices** (in recommended order): snapshot structs
  (`GhosttyTerminalSnapshot`/`TerminalTabSnapshot` — clean but needs typealias
  shims for ~40 external refs), AppleScript source-string constants, then the
  seam-requiring pieces (`runAppleScript`/`isRunning`) only after an injection
  seam exists; `corrected*JumpTarget` last (not identical — needs Resolver flow
  tests first).
