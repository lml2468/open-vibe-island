---
type: Journal
title: "Journal: dedup-installer-hookmarkers"
description: Centralized the Open Island hook-marker substring literals into a shared OpenIslandHookMarkers helper; kept each installer's divergent gating split so the safety-critical managed-vs-user decision stays locally auditable
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T09:10:00Z
slug: dedup-installer-hookmarkers
source: self
---

# Journal: dedup-installer-hookmarkers

Eighteenth implemented slice of the `arch-quality-audit-r2` discovery — the third
cluster-B cut. See `.octospec/tasks/dedup-installer-hookmarkers/brief.md` (r1, approved).

## What was done

The 5 installer command-detection predicates each hardcoded the same brand-alias
substrings. Two atoms recurred: the **hooks marker**
(`openislandhooks`/`vibeislandhooks`, all 5) and the **bridge marker**
(`open-island-bridge`/`vibe-island-bridge`, Claude/Codex/Kimi). Extracted them into
`OpenIslandHookMarkers.hasHooksMarker/hasBridgeMarker` and substituted the two
`contains(…) || contains(…)` clusters in each predicate for a helper call — a pure
literal substitution. Each predicate keeps its **exact divergent gating**
(Claude asymmetric `--source claude`-for-hooks + bare-`claude`-for-bridge; Codex
ungated; Cursor/Gemini bare-name hooks-only; Kimi `--source kimi` over both).
Predicates relaxed `private`→`internal` so their truth tables can be pinned by
direct tests. `HookHealthCheck.swift`'s own marker checks are a separate,
non-installer file — deliberately left out of scope.

## Verification

- New `OpenIslandHookMarkersTests`: A1 marker-atom tests (both alias families,
  cross-family negatives) + A2 per-predicate truth-table tests for all 5 installers
  capturing each distinguishing case.
- TDD trail: `red:` (7e92cea) stubbed both atoms to return `false` (A1 failed) +
  relaxed visibility; A2 truth-table tests PASSED at red against the unchanged
  inline bodies — the behavior-neutrality guard. Green (9279fb0) implemented the
  atoms + substituted the clusters; `git diff red..green -- Tests/` = 0 bytes.
- Independent Verify (fresh context) PASS, no findings — confirmed each of the 5
  predicates' Green body differs from main ONLY by the two cluster→helper
  substitutions (gating tokens, AND/OR structure, control flow, `.lowercased()` all
  unchanged), the atoms are byte-equivalent to the removed clusters, and
  HookHealthCheck was untouched. Gate green: `harness.sh ci` (463 tests), exit 0.

## Learning

- **When N call sites share drift-prone *literals* but *divergent logic*, centralize
  the literals and leave the logic split.** The alias substrings were the real
  copy-paste hazard (one past brand rename already; the next alias means editing 5/3
  sites in lockstep, and a missed site is a silent config-safety bug — a managed hook
  no longer recognized survives uninstall, or a user's hook gets deleted). But the
  *gating* around those literals genuinely differs per agent and drives a
  delete-vs-keep decision, so folding it into one parameterized predicate would bury
  safety-critical branching in a per-call argument list. Extracting only the atoms
  removes the drift risk while keeping each decision locally auditable. Resist the
  pull to "finish the job" by unifying the predicates too.
- **A pure-relocation dedup gets its behavior-neutrality proof for free from the
  *existing* callers' tests — but pin the extracted unit's truth table at the call
  boundary anyway.** Here the A2 tests target the predicates directly (via a
  `private`→`internal` relaxation), so a future edit to a *predicate* is caught even
  if the higher-level installer round-trip suites don't happen to exercise that exact
  marker/gate combination. The visibility relaxation is itself the seam; note it as
  behavior-neutral in the brief so Verify doesn't flag it.
- **Cluster B remaining is the structural tier:** the `sanitize`/hook-array mutators
  (the actual config-write surface) and the manager `status/install/uninstall`
  base-class extraction (needs a protocol with associated Status types). All three
  pure-literal/helper extractions (serialize, loadRootObject, hook markers) are now
  done. Also noted for a future slice: `HookHealthCheck.swift` still inlines the same
  4 marker literals (lines ~306/344/404) — a candidate to route through
  `OpenIslandHookMarkers` too.
