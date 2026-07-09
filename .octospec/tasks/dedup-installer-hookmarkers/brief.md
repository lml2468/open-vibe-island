---
type: Task
title: "Task: dedup-installer-hookmarkers"
description: Centralize the Open Island hook-marker substring literals into a shared OpenIslandHookMarkers helper; keep each installer's divergent gating logic split
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T08:16:10Z
# --- octospec extension fields ---
slug: dedup-installer-hookmarkers
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — third cut)
source: self
revision: 1
approvals: []
---

# Task: dedup-installer-hookmarkers

> Eighteenth slice of the `arch-quality-audit-r2` discovery — the third cluster-B
> cut. Deliberately narrow: extract only the drift-prone **marker literals** from
> the 5 command-detection predicates; leave their divergent gating split.
> Independent branch off `origin/main`.

## Goal

The 5 installer command-detection predicates (Claude/Codex/Cursor/Gemini/Kimi
`is…HookCommand`) each hardcode the same Open Island brand-alias substrings to
decide whether a command is a managed/legacy hook. Two marker atoms recur:
- **hooks marker:** `contains("openislandhooks") || contains("vibeislandhooks")`
  — in **all 5**.
- **bridge marker:** `contains("open-island-bridge") || contains("vibe-island-bridge")`
  — in **3** (Claude/Codex/Kimi).

Extract just these two atoms into `OpenIslandHookMarkers.hasHooksMarker(_:)` /
`hasBridgeMarker(_:)` (a new OpenIslandCore helper, operating on an
already-lowercased string). Replace the two `contains(…) || contains(…)` clusters
in each predicate with a call, keeping every predicate's **exact current AND/OR
gating structure** in place. This is a literal substitution → behavior-neutral.

**Deliberately NOT unifying the predicates themselves.** Their gating genuinely
diverges (Claude: `--source claude` for hooks + bare `claude` for bridge; Codex:
ungated; Cursor/Gemini: bare agent-name, hooks-only; Kimi: `--source kimi` over
both), and each drives which hook entries get **deleted** during sanitize/uninstall
— so a wrong match drops a user's non-managed hook or leaves a stale one. A single
parameterized predicate would push all that safety-critical gating into a per-call
argument list; keeping it split and locally auditable is the safer choice
(`installer-config-safety`). Only the drift-prone literals are centralized.

## Background

- Rationale for centralizing the literals: the project already did one brand rename
  (open-island → vibe-island); the next alias addition today means editing 5 (hooks)
  / 3 (bridge) sites in lockstep, and a missed site is a silent config-safety bug
  (a managed hook no longer recognized → survives uninstall, or vice versa).
- The predicates are `private static func … (String) -> Bool`, pure, but currently
  unreachable from tests (`@testable` exposes `internal`, not `private`). Relax the
  5 predicates from `private` to `internal` (a behavior-neutral visibility change)
  so their truth tables can be pinned by **direct** failing-first tests.
- **Injected rule:** `installer-config-safety` (load-bearing). The gating that
  decides managed-vs-user hooks is unchanged; only the marker literals move.
- Mirrors the `ShellQuoting`/`JSONConfigSerialization` shared-helper precedent.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 5 predicates** (`ClaudeHookInstaller.swift:289`, `CodexHookInstaller.swift:393`,
  `CursorHookInstaller.swift:143`, `GeminiHookInstaller.swift:150`,
  `KimiHookInstaller.swift:204`) — the two marker clusters replaced by helper calls;
  gating structure + `private`→`internal` only. Their truth tables must be
  identical before/after. `[installer] [config]`
- **New `OpenIslandHookMarkers`** — the shared marker atoms; its two funcs define
  which brand aliases count. `[config]`
- **The sanitize/uninstall/status flows** that call each predicate — unchanged
  behavior (which hooks are treated as managed / deleted). `[installer] [config]`

## Out of scope
- **Unifying the predicates into one parameterized `isOpenIslandHookCommand`** —
  the gating divergence is real and safety-critical; keep it split (this is a
  deliberate decision, per the scope analysis, not an oversight).
- **`sanitize`/hook-array mutators** and the **manager base-class** extraction —
  the remaining, riskier cluster-B pieces.
- No change to any predicate's truth table, to gating tokens, or to config-write
  behavior beyond the literal-substitution + visibility relaxation.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `OpenIslandHookMarkers` matches both alias families.** `hasHooksMarker`
  is true for a string containing `"openislandhooks"` and for one containing
  `"vibeislandhooks"`, false otherwise; `hasBridgeMarker` is true for
  `"open-island-bridge"` and `"vibe-island-bridge"`, false otherwise. *(Testable:
  direct unit test. Fails first — the helper does not exist.)*
- **A2 — each predicate's truth table is preserved (captured directly).** With the
  predicates made `internal`, direct tests assert the current behavior of all 5,
  including the distinguishing cases: Codex matches an ungated marker; Cursor/Gemini
  require the bare agent name AND ignore the bridge family; Claude uses
  `--source claude` for hooks but bare `claude` for bridge; Kimi requires
  `--source kimi` for both. *(Testable: per-predicate truth-table tests. These
  characterize current behavior and must stay green through the extraction —
  behavior-neutrality guard. They pass at red for the existing bodies.)*
- **A3 — the marker literals live in exactly one place.** No installer predicate
  contains the raw `"openislandhooks"`/`"vibeislandhooks"`/`"open-island-bridge"`/
  `"vibe-island-bridge"` substrings inline; all route through
  `OpenIslandHookMarkers`. *(Verifiable by grep — the 4 literals appear only in
  `OpenIslandHookMarkers`.)*
- **A4 — behavior neutral + gate green.** Existing installer suites
  (`ClaudeHooksTests`/`CursorHooksTests`/`GeminiHooksTests`/`KimiHooksTests` +
  Codex, incl. the markerless-fallback uninstall tests) pass unchanged; `swift build`
  + `swift test` pass under the repo gate (warnings-as-errors + `swiftlint --strict`).
  *(N/A(test): the gate + existing suites are the behavior-neutral proof.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
