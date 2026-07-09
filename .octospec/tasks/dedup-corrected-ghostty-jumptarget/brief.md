---
type: Task
title: "Task: dedup-corrected-ghostty-jumptarget"
description: Dedup correctedGhosttyJumpTarget (incl. the Zellij guard) into shared TerminalProbeSupport — behavior-neutral because the guard is provably dead in the Resolver, live in the Probe
tags: ["dedup", "terminal", "jump", "correctness"]
timestamp: 2026-07-09T06:49:27Z
# --- octospec extension fields ---
slug: dedup-corrected-ghostty-jumptarget
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A — final piece)
source: self
revision: 1
approvals: []
---

# Task: dedup-corrected-ghostty-jumptarget

> Fifteenth slice of the `arch-quality-audit-r2` discovery — the **last** real
> cluster-A dedup, resolving the one divergence that blocked the earlier
> corrected-target slice. Independent branch off `origin/main`.

## Goal

`correctedGhosttyJumpTarget(for:snapshot:)` is duplicated between
`TerminalJumpTargetResolver.swift:193-235` and
`TerminalSessionAttachmentProbe.swift:740-789`. The two bodies differ by **exactly
one** thing — the Probe has a 7-line Zellij early-return guard the Resolver lacks
(verified: `diff` of the two bodies shows only that hunk):
```swift
// Zellij runs inside Ghostty but has its own jump-back mechanism
// via pane IDs. Don't overwrite Zellij's terminal info with
// Ghostty's session ID, as it would break Zellij pane targeting.
if jumpTarget.terminalApp.lowercased() == "zellij" {
    return nil
}
```
Extract ONE shared `TerminalProbeSupport.correctedGhosttyJumpTarget(for:snapshot:)`
**including the guard**, and have both callers delegate. This is **behavior-neutral**
because the guard is provably **dead in the Resolver** and **live in the Probe**
(see the reachability proof below) — so the merged body preserves each caller's
observable behavior without needing an `applyZellijGuard` flag.

## Reachability proof (why merging with the guard is behavior-neutral)

**In the Resolver the guard can never fire** — two entry paths, both excluded:
1. **Existing-jumpTarget path.** `resolveJumpTargets`'s Ghostty candidate filter
   (`TerminalJumpTargetResolver.swift:91-93`) admits a session only if
   `normalizedTerminalName($0.jumpTarget?.terminalApp) == "ghostty"` OR
   `($0.jumpTarget?.terminalApp == nil && $0.jumpTarget == nil)`. A zellij-labelled
   session normalizes to `"zellij"` (not `"ghostty"`) and has a non-nil jumpTarget,
   so it fails **both** disjuncts → never reaches `correctedGhosttyJumpTarget`.
2. **Nil-jumpTarget path.** The only other admitted case is a fully-nil jumpTarget;
   inside `correctedGhosttyJumpTarget` the seed (`:198-204`) hardcodes
   `terminalApp: "Ghostty"`, so `jumpTarget.terminalApp.lowercased() == "zellij"`
   is false there too.

**In the Probe the guard is live** — `sessionResolutionReport` builds
`ambiguousSessions` (`TerminalSessionAttachmentProbe.swift:169`) as a catch-all
that does NOT exclude `"zellij"`, feeds it to the Ghostty resolution
(`:184`), so a zellij session reaches `correctedGhosttyJumpTarget` and the guard
correctly returns nil (preventing Ghostty from overwriting Zellij's pane
targeting).

Therefore the shared body (with the guard) behaves identically to today for both
callers: Resolver output unchanged (guard inert), Probe output unchanged (guard
already present).

## Background

- Depends on `normalizedTerminalName` (already a shared delegate) and
  `nonEmptyValue` (shared as of the prior slice) — both already in
  `TerminalProbeSupport`, and `GhosttyTerminalSnapshot` is a shared top-level type,
  so the shared signature compiles with no extra plumbing.
- The extracted method becomes a non-private static → the guard itself gets a
  **real** direct unit test (a zellij-labelled jumpTarget → nil).
- **Honest limitation (flag to reviewer):** the "behavior-neutral for the
  Resolver" claim rests on the **static reachability argument above**, not on a
  test that isolates the guard in the Resolver. `resolveJumpTargets` fetches
  Ghostty snapshots via the injected seam, so a Resolver-level test could assert a
  zellij session yields no jump-target update — but that's already guaranteed by
  the entry filter, so it can't attribute the outcome to the guard specifically.
  The direct unit test proves the guard's behavior; the reachability proof is the
  neutrality argument.
- **Injected rule:** `terminal-jump-resilience` (touches: jump).

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 2 `correctedGhosttyJumpTarget` copies** (`TerminalJumpTargetResolver.swift:193`,
  `TerminalSessionAttachmentProbe.swift:740`) — become one-line delegates to the
  shared static (which includes the guard). `[terminal] [jump] [correctness]`
- **New `TerminalProbeSupport.correctedGhosttyJumpTarget`** — the shared home
  (with the Zellij guard); its output defines correctness. `[jump]`
- **The Resolver candidate filter (`:91-93`) + the seed (`:198-204`)** — the basis
  of the dead-guard proof; must be unchanged (the neutrality argument depends on
  them). `[jump]`
- **The Probe's `ambiguousSessions` path (`:169,:184`)** — where the guard is live;
  unchanged. `[jump]`

## Out of scope
- **The resolver's two inline non-throwing osascript blocks** — different shape;
  separate (or no) slice. After this, cluster A is complete.
- No change to the entry filters, the seed, or any correction logic beyond
  merging the two bodies into one (guard included).

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — shared `correctedGhosttyJumpTarget` applies the Ghostty corrections.**
  Given a session with a stale non-Ghostty jumpTarget + a `GhosttyTerminalSnapshot`,
  the shared static returns a JumpTarget with `terminalApp == "Ghostty"`,
  `terminalSessionID == snapshot.sessionID`, `workingDirectory ==
  snapshot.workingDirectory`, `paneTitle == snapshot.title`. *(Testable: direct
  call. Fails first — the static does not exist.)*
- **A2 — the Zellij guard returns nil.** With a session whose `jumpTarget.terminalApp
  == "zellij"` (and "Zellij"), the shared static returns `nil` (does not overwrite
  it with Ghostty info). *(Testable: direct call. Fails first.)*
- **A3 — synthesizes a JumpTarget when the session has none.** With
  `session.jumpTarget == nil`, the shared static returns a JumpTarget seeded from
  the snapshot with `terminalApp == "Ghostty"` (changed == true path). *(Testable:
  direct call. Fails first.)*
- **A4 — both callers delegate; one definition remains.** Neither probe file
  contains the `correctedGhosttyJumpTarget` correction body inline; both are
  one-line delegates to `TerminalProbeSupport`. *(Verifiable by grep — the
  `terminalSessionID = snapshot.sessionID` / guard body exists in exactly one
  place.)*
- **A5 — behavior neutral + gate green.** Existing
  `TerminalSessionAttachmentProbeTests` (which exercise both callers' Ghostty
  paths, including the Probe's zellij handling) + `AppModelSessionListTests` pass
  unchanged; `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate + existing
  suites are the behavior-neutral proof for both callers.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
