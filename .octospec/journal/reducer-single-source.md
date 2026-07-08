---
type: Journal
title: "Journal: reducer-single-source"
description: Centralized the don't-resurrect-an-ended-session guard in SessionState (closing two unguarded apply paths) and deduped the fork-tool list into isClaudeCodeFork
tags: ["reducer", "session-state", "correctness", "dedup"]
timestamp: 2026-07-08T12:20:00Z
slug: reducer-single-source
source: self
---

# Journal: reducer-single-source

Third implemented slice of the `arch-quality-audit-r2` discovery (findings #7,
#19). Contained to `SessionState.swift`, backed by the existing 43→48-case
`SessionStateTests`.

## What was done

1. **Centralized the terminal guard (#7).** Added one private
   `isTerminalAndMustNotResurrect(_:)` as the single expression of the
   "don't resurrect an ended session" invariant. `apply(.activityUpdated)`,
   `resolvePermission`, and `answerQuestion` (which each hand-rolled the check)
   now route through it — and the two `apply` paths that **forgot** it,
   `.permissionRequested` and `.questionAsked`, are now guarded. That last part is
   a real behavior fix: before, an out-of-order permission/question event for an
   already-ended session revived it into a `.waitingFor…` phase that inflated the
   actionable count yet was invisible in the island. (`actionableStateResolved`
   was left as-is — it early-returns unless already in a waiting phase, so an
   ended `.completed` session can't reach its `phase = .running`; verified safe.)
2. **Deduped the fork list (#19).** `resolvePermission` hand-inlined the
   Claude-fork tool set twice while `AgentTool.isClaudeCodeFork` sat unused (dead
   code). Replaced both switches with `isClaudeCodeFork || tool == .geminiCLI` —
   `isClaudeCodeFork` deliberately excludes `.geminiCLI`, so the `|| .geminiCLI`
   preserves the exact prior membership and every summary string byte-for-byte.

## Verification

- New `SessionStateTests` (6): A1 `permissionRequested`/A2 `questionAsked` do not
  resurrect an ended session (failed first on the real bug), A3 live sessions
  still transition, A4 approved/denied summary strings unchanged per tool
  (all 7 forks + gemini + openCode + codex), `isClaudeCodeFork` membership stable.
- TDD trail: `red:` (A1/A2 fail on the unguarded paths; A3/A4/membership pass as
  preservation guards) → Green did not touch tests (`git diff red..green --
  Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS, no findings — confirmed the
  string-equivalence byte-for-byte and that `isClaudeCodeFork` is no longer dead.
- Gate green: `harness.sh ci` — 400 tests / 49 suites, warnings-as-errors +
  `swiftlint --strict`, exit 0.

## Learning

- **A "centralize the duplicated guard" refactor is also a bug hunt.** The value
  wasn't the shared helper per se — it was that collecting every phase-changing
  path into one invariant *surfaced the two paths that never had the guard*
  (`permissionRequested`/`questionAsked`). When a rule says "this invariant is
  duplicated across N methods," enumerate ALL the sites that should hold it; the
  ones missing from the list are the latent bugs. Updated the
  `session-state-invariants` rule to record that the centralization is now done.
- **Dedup against a helper only after checking membership equality.** The dead
  `isClaudeCodeFork` looked like a drop-in for the inlined list but omitted
  `.geminiCLI`; a naive swap would have silently changed gemini's summary. A4
  pins the exact strings per tool so the equality is proven, not assumed —
  mirrors the "prove format stability with a fixture" lesson from
  `dedup-registries`.
