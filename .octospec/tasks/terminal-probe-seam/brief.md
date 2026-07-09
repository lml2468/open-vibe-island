---
type: Task
title: "Task: terminal-probe-seam"
description: Add injectable appleScriptRunner + appRunningChecker seams (defaulted) to the two terminal probe types, unlocking real unit tests for their parse/availability logic
tags: ["testability", "applescript", "terminal", "seam"]
timestamp: 2026-07-09T05:41:25Z
# --- octospec extension fields ---
slug: terminal-probe-seam
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A — enabler)
source: self
revision: 1
approvals: []
---

# Task: terminal-probe-seam

> Twelfth slice of the `arch-quality-audit-r2` discovery — the enabler for the
> remaining cluster-A dedup. Adds injection seams to the two terminal probe types
> so their AppleScript-based logic becomes unit-testable (turning the previously
> `N/A(test)` cluster into real failing-first tests). Independent branch off
> `origin/main`.

## Goal

`TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe` currently
hardcode `runAppleScript` (spawns `/usr/bin/osascript` via `Process`) and
`isRunning(bundleIdentifier:)` (`NSRunningApplication` global state), and construct
via bare `()` — so their parse and availability logic is untestable. Add two
**injectable, defaulted** closures to BOTH types (mirroring the existing
`TerminalJumpService` seam pattern):
- `appleScriptRunner: @Sendable (String) throws -> String` — default = each type's
  current `Process`-based `runAppleScript` impl (kept as-is, incl. its own NSError
  domain + `appleScriptTimeout`).
- `appRunningChecker: @Sendable (String) -> Bool` — default =
  `NSRunningApplication.runningApplications(withBundleIdentifier:).isEmpty == false`.

Route the existing `runAppleScript`/`isRunning` bodies through the injected
closures (the private methods become thin delegates, so their ~5 + ~6 call sites
are untouched). Every init param is **defaulted**, so all 25 existing bare-`()`
constructions (2 production + 23 test) keep compiling — zero breakage.

**No dedup in this slice** — the default impls stay per-type (the resolver keeps
timeout `3` / domain `"TerminalJumpTargetResolver"`, the probe keeps `1.0` /
`"TerminalSessionAttachmentProbe"`). Consolidating them into a shared
`TerminalProbeSupport` helper is the trivially-behavior-neutral **next** slice,
guarded by the tests this slice adds.

## Background

- **Pattern to mirror:** `TerminalJumpService.swift:6-9` (typealiases),
  `:214-254` (defaulted-closure init), tested via injected fakes in
  `TerminalJumpServiceTests.swift:99-109`.
- **runAppleScript** is instance, `private func … throws -> String`
  (`TerminalJumpTargetResolver.swift:749`, `TerminalSessionAttachmentProbe.swift:1273`)
  — byte-identical except NSError domain + `appleScriptTimeout` (3 vs 1.0). Call
  sites: resolver 2 (`:673,:698`), probe 3 (`:1176,:1197,:1247`).
- **isRunning** is byte-identical
  (`TerminalJumpTargetResolver.swift:745`, `TerminalSessionAttachmentProbe.swift:1269`).
  Call sites: resolver 3, probe 3 (the `*SnapshotAvailability()` wrappers).
- **What the seam unlocks (the real tests):**
  - inject `appRunningChecker = { false }` → `ghosttySnapshotAvailability()` returns
    `.available([], appIsRunning: false)` with no running app;
  - inject `appleScriptRunner = { <canned field(31)/record(30)-delimited string> }`
    + `appRunningChecker = { true }` → the availability wrapper returns the parsed
    `[GhosttyTerminalSnapshot]`, exercising the `ghosttySnapshots()` parse logic
    that is untestable today.
- `SnapshotAvailability` and the `*SnapshotAvailability()` methods are already
  `internal` → reachable via `@testable import`. `TerminalJumpTargetResolver` has
  no test file yet; this adds one.
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump).

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`TerminalSessionAttachmentProbe` init + `runAppleScript`/`isRunning`**
  (`:1269,:1273`, new init) — gains the two defaulted closures; the private methods
  delegate to them. `[applescript] [terminal] [seam]`
- **`TerminalJumpTargetResolver` init + `runAppleScript`/`isRunning`**
  (`:745,:749`, new init) — same. `[applescript] [terminal] [seam]`
- **The `*SnapshotAvailability()` + `*Snapshots()` parse methods** (probe
  `:1125-1215`) — behavior unchanged; now reachable in tests via the seam. `[applescript]`
- **All 25 bare-`()` construction sites** (`ProcessMonitoringCoordinator.swift:50,53`;
  23 test sites) — must keep compiling unchanged (defaulted params). `[terminal]`

## Out of scope
- **Deduping `runAppleScript`/`isRunning` into `TerminalProbeSupport`** — the next
  slice, guarded by this slice's tests. Defaults stay per-type here.
- **The two inline `osascript` blocks in the resolver** (`~:360-400,~:615-640`) —
  different return-nil control flow; separate finding.
- **`corrected*JumpTarget`** (Ghostty variant differs — Probe Zellij guard).
- `TerminalTextSender`/`ForegroundTerminalSessionProbe` runAppleScript variants
  (different signatures) — not this pair.
- No production behavior change (a defaulted seam reproduces today's behavior);
  no change to timeout values, NSError domains, or the AppleScript text.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — an injected `appRunningChecker` short-circuits availability.** With
  `TerminalSessionAttachmentProbe(appRunningChecker: { _ in false })`,
  `ghosttySnapshotAvailability()` returns `.available([], appIsRunning: false)`
  (and does NOT invoke the AppleScript runner). *(Testable: inject the fake; assert
  the result + that the runner was not called. Fails first — no such init param
  exists.)*
- **A2 — an injected `appleScriptRunner` drives the parse logic.** With
  `appRunningChecker: { _ in true }` and `appleScriptRunner` returning a canned
  field-separator(31)/record-separator(30)-delimited two-terminal payload,
  `ghosttySnapshotAvailability()` returns `.available([two GhosttyTerminalSnapshots
  with the expected sessionID/workingDirectory/title], appIsRunning: true)`.
  *(Testable: inject fakes; assert the parsed snapshots. Fails first — the runner
  isn't injectable.)*
- **A3 — a throwing `appleScriptRunner` yields `.unavailable`.** With
  `appRunningChecker: { _ in true }` and an `appleScriptRunner` that throws,
  `ghosttySnapshotAvailability()` returns `.unavailable(appIsRunning: true)`.
  *(Testable: inject a throwing fake; assert `.unavailable`. Fails first.)*
- **A4 — the resolver seam is injectable too.** `TerminalJumpTargetResolver` accepts
  injected `appleScriptRunner`/`appRunningChecker`; a fake `appRunningChecker` is
  consulted by its logic (e.g. an `isRunning`-gated path observes the injected
  value). *(Testable: construct with a recording fake; assert it's used. Fails
  first — no init param.)*
- **A5 — no construction breakage + gate green.** All existing bare-`()`
  constructions (`ProcessMonitoringCoordinator` + the 23 test sites) still compile;
  the existing `TerminalSessionAttachmentProbeTests`/`AppModelSessionListTests`
  pass unchanged; `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself; the
  existing suites prove the defaulted seam is behavior-neutral.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
