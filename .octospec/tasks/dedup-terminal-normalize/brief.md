---
type: Task
title: "Task: dedup-terminal-normalize"
description: Extract the duplicated normalizedTerminalName into a shared TerminalProbeSupport helper — the first, smallest cut of the AppleScript probe cluster (finding #9 A)
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T04:26:04Z
# --- octospec extension fields ---
slug: dedup-terminal-normalize
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A)
source: self
revision: 1
approvals: []
---

# Task: dedup-terminal-normalize

> Ninth slice of the `arch-quality-audit-r2` discovery — the first, smallest,
> lowest-risk cut of finding #9 **cluster A** (the Terminal AppleScript probe
> duplication between `TerminalJumpTargetResolver` and
> `TerminalSessionAttachmentProbe`). Establishes the shared-home file that later
> cluster-A slices grow into. Independent branch off `origin/main`.

## Goal

Extract the duplicated `normalizedTerminalName(for:)` — currently a private method
in **both** `TerminalJumpTargetResolver.swift:790-792` and
`TerminalSessionAttachmentProbe.swift:1312-1316`, byte-identical logic
(`value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()`, differing
only in cosmetic line-wrapping) — into one shared, unit-tested helper:
`TerminalProbeSupport.normalizedTerminalName(for:)` in a new
`Sources/OpenIslandApp/TerminalProbeSupport.swift`.

**Keep both existing private methods as thin forwarders** that call the shared
helper. This means only the **two method bodies** change; all 15 call sites
(8 in Resolver, 7 in Probe) keep calling `normalizedTerminalName(for:)`
unchanged — a provably behavior-neutral extraction with minimal churn.

Behavior is unchanged (the two copies are already identical); this is pure
de-duplication that also creates the `TerminalProbeSupport` shared home for the
next cluster-A cuts (snapshot structs, AppleScript source strings).

## Background

- Both files are in the **OpenIslandApp** target with bare `()` initializers and
  **no command-runner / appleScriptRunner injection seam** — so the risky parts
  of cluster A (`runAppleScript`, `isRunning`, the AppleScript source strings,
  `corrected*JumpTarget`) are NOT cleanly unit-testable and are deferred. This
  slice takes the one piece that IS a pure, testable function.
- Mirrors the merged `dedup-shellquote` / `dedup-escape-applescript` pattern:
  extract a pure helper into a shared type + a real unit test, prove neutrality
  via the callers' existing tests. `TerminalSessionAttachmentProbe` is well-tested
  (`TerminalSessionAttachmentProbeTests`, ~40 cases via `sessionResolutionReport`);
  `TerminalJumpTargetResolver` currently has **no** test file.
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump).
  This change is behavior-neutral to the jump/probe paths — the normalization it
  governs must be preserved exactly.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 2 `normalizedTerminalName` definitions** (`TerminalJumpTargetResolver.swift:790`,
  `TerminalSessionAttachmentProbe.swift:1312`) — become thin forwarders to the
  shared helper. `[terminal] [applescript]`
- **The 15 call sites** (8 Resolver + 7 Probe) — unchanged; their resolved
  terminal-name values must be identical before/after. `[terminal]`
- **New `TerminalProbeSupport.normalizedTerminalName`** — the shared home; its
  output defines correctness. `[terminal]`

## Out of scope
- **Everything else in cluster A** — the snapshot structs
  (`GhosttyTerminalSnapshot`/`TerminalTabSnapshot`), the Ghostty/Terminal
  AppleScript source strings, `runAppleScript`, `isRunning`, and the
  `corrected*JumpTarget` logic (the Ghostty variant is NOT identical — the Probe
  has a Zellij guard). Each is its own later slice.
- **No injection-seam refactor** of the two probe types.
- No change to any AppleScript, jump/probe behavior, or public API beyond adding
  `TerminalProbeSupport`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `TerminalProbeSupport.normalizedTerminalName` trims and lowercases.** It
  returns `nil` for nil input; lowercases (`"Ghostty"` → `"ghostty"`); trims
  surrounding whitespace/newlines (`"  Ghostty \n"` → `"ghostty"`); maps a
  whitespace-only string to `""`; and leaves an already-normalized value unchanged
  (`"iterm"` → `"iterm"`). *(Testable: direct unit test of the pure function.
  Fails first — the helper does not exist.)*
- **A2 — both private methods forward to the shared helper (behavior neutral).**
  The Resolver and Probe still resolve the same normalized terminal names for
  representative inputs, and their existing test suites pass unchanged.
  *(Testable: the existing `TerminalSessionAttachmentProbeTests` still pass;
  equivalently the shared helper's output equals the pre-extraction bodies'.
  Preservation guard.)*
- **A3 — no duplicated `normalizedTerminalName` BODY remains.** Each private method
  is a one-line forwarder to `TerminalProbeSupport`; the
  `trimmingCharacters(...).lowercased()` logic exists in exactly one place.
  *(Verifiable by grep / reading the two now-forwarding methods.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
