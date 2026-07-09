---
type: Task
title: "Task: dedup-corrected-terminal-jumptarget"
description: Dedup the byte-identical correctedTerminalJumpTarget (and lift nonEmptyValue) into shared TerminalProbeSupport; defer the diverging Ghostty variant
tags: ["dedup", "terminal", "jump", "maintainability"]
timestamp: 2026-07-09T06:34:19Z
# --- octospec extension fields ---
slug: dedup-corrected-terminal-jumptarget
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A)
source: self
revision: 1
approvals: []
---

# Task: dedup-corrected-terminal-jumptarget

> Fourteenth slice of the `arch-quality-audit-r2` discovery — a cluster-A dedup
> of the byte-identical Terminal.app jump-target correction, with a real direct
> unit test (enabled by making it a shared static). Independent branch off
> `origin/main`.

## Goal

`correctedTerminalJumpTarget(for:snapshot:)` is **byte-identical** between
`TerminalJumpTargetResolver.swift:445-472` and
`TerminalSessionAttachmentProbe.swift:791-818` — a pure `(AgentSession,
TerminalTabSnapshot) -> JumpTarget?` transform. Extract it into
`TerminalProbeSupport.correctedTerminalJumpTarget(for:snapshot:)` and reduce both
private copies to one-line delegates.

Its body calls `nonEmptyValue(_:)`, which is also a byte-identical private copy in
both files (24 refs each). Lift `nonEmptyValue` into
`TerminalProbeSupport.nonEmptyValue(_:)` too, keeping each file's private copy as a
thin delegate (so all 23 existing call sites per file stay untouched) — the shared
`correctedTerminalJumpTarget` then calls the shared `nonEmptyValue`.

Behavior is unchanged (identical pure functions moved verbatim); this consolidates
the correction logic and, because the extracted method becomes a non-private
`static`, gives it a **real** direct unit test.

## Background

- **The Ghostty variant is deliberately deferred.**
  `correctedGhosttyJumpTarget` is NOT identical — the Probe version has an extra
  `if jumpTarget.terminalApp.lowercased() == "zellij" { return nil }` guard the
  Resolver lacks. Deduping it would either change Resolver behavior (apply the
  guard where it isn't today) or bake an `applyZellijGuard: Bool` flag into the
  shared API — neither is a behavior-neutral dedup. That is its own follow-up
  decision slice (prove the guard is unreachable in the Resolver, or accept it as
  an intentional behavior change), NOT this slice.
- Dependency tree is shallow: `correctedTerminalJumpTarget → {normalizedTerminalName
  (already a shared delegate), nonEmptyValue (lifted here)}`. No seam/`isRunning`/
  live-state calls — it's pure.
- Reachability: the method is exercised today via the Probe's
  `sessionResolutionReport(...)` (`TerminalSessionAttachmentProbeTests` asserts
  `correctedJumpTarget.*`), and once extracted as a non-private static it's also
  **directly** unit-testable.
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump).

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 2 `correctedTerminalJumpTarget` copies** (`TerminalJumpTargetResolver.swift:445`,
  `TerminalSessionAttachmentProbe.swift:791`) — become one-line delegates to the
  shared static. `[terminal] [jump]`
- **The 2 `nonEmptyValue` copies** (`:755`, `:1180`) — become thin delegates to a
  shared `TerminalProbeSupport.nonEmptyValue`; their 23 call sites each are
  untouched. `[terminal]`
- **New `TerminalProbeSupport.correctedTerminalJumpTarget` + `.nonEmptyValue`** —
  the shared home; outputs must match the removed bodies exactly. `[jump]`
- **The call sites** (`resolveJumpTargets` Terminal branch; Probe
  `sessionResolutionReport` Terminal resolution) — unchanged; the corrected
  JumpTarget they produce must be identical. `[jump]`

## Out of scope
- **`correctedGhosttyJumpTarget`** — deferred (Zellij-guard divergence; its own
  behavioral decision slice).
- **The resolver's two inline non-throwing osascript blocks** — separate shape.
- **`isRunning`/`appRunningChecker`** — default already effectively shared.
- No behavior change, no change to the correction logic, no seam-API change.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — shared `correctedTerminalJumpTarget` applies the corrections.** Given a
  session whose `jumpTarget` has a stale `terminalApp`/`terminalTTY`/`paneTitle`
  and a `TerminalTabSnapshot(tty:customTitle:)`,
  `TerminalProbeSupport.correctedTerminalJumpTarget(for:snapshot:)` returns a
  JumpTarget with `terminalApp == "Terminal"`, `terminalTTY == snapshot.tty`, and
  `paneTitle == snapshot.customTitle`. *(Testable: direct call on the shared
  static. Fails first — the static does not exist.)*
- **A2 — returns nil when nothing changed / no jumpTarget.** With a session whose
  jumpTarget already matches the snapshot (Terminal app, same tty, same title) it
  returns `nil`; with `session.jumpTarget == nil` it returns `nil`. *(Testable:
  direct call. Fails first.)*
- **A3 — shared `nonEmptyValue` trims + nils empties.** Returns the trimmed value
  for non-empty input, `nil` for nil / whitespace-only. *(Testable: direct call.
  Fails first.)*
- **A4 — no duplicated body remains; both files delegate.** Neither probe file
  contains the `correctedTerminalJumpTarget` correction body nor a
  `nonEmptyValue` trim body inline — both are one-line delegates to
  `TerminalProbeSupport`. *(Verifiable by grep + the delegates reading as
  one-liners.)*
- **A5 — behavior neutral + gate green.** Existing
  `TerminalSessionAttachmentProbeTests` + `AppModelSessionListTests` +
  `TerminalProbeSupportTests`/`TerminalProbeSeamTests` pass unchanged; `swift build`
  + `swift test` pass under the repo gate (warnings-as-errors + `swiftlint
  --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
