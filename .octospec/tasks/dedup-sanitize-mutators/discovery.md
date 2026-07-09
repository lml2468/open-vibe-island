---
type: Note
title: "Discovery: dedup-sanitize-mutators"
description: The Claude and Codex hook-array walkers (sanitize / sanitizeForInstall / containsManagedHook) are byte-identical; extract a shared closure-parameterized helper while keeping each installer's divergent leaf predicate split
tags: ["discovery"]
timestamp: 2026-07-09T09:20:00Z
# --- octospec extension fields ---
slug: dedup-sanitize-mutators
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — fourth cut)
source: self
---

# Discovery: dedup-sanitize-mutators

> The **Discover** phase output. Read-only exploration done BEFORE the brief.
> Nineteenth slice of the `arch-quality-audit-r2` audit; fourth cluster-B cut.
> The three pure-helper extractions (serialize, loadRootObject, hook markers) are
> merged; this is the first cluster-B cut touching the actual config-write
> (delete-driving) surface.

## Relevant files
- `Sources/OpenIslandCore/ClaudeHookInstaller.swift` — the group→hooks array
  walkers `sanitize(groups:managedCommand:)` (L155-177),
  `sanitizeForInstall(groups:replacingCommand:)` (L179-201),
  `containsManagedHook(in:managedCommand:)` (L203-218); leaf predicates
  `isManagedHook` (L265-275), `isManagedHookForInstall` (L277-287).
- `Sources/OpenIslandCore/CodexHookInstaller.swift` — the **byte-identical** twin
  walkers `sanitize` (L287-309), `sanitizeForInstall` (L311-333),
  `containsManagedHook` (L335-350); **divergent** leaf `isManagedHook` (L368-379,
  statusMessage-first) + `isManagedHookForInstall` (L381-391).
- `Sources/OpenIslandCore/CursorHookInstaller.swift`, `GeminiHookInstaller.swift`,
  `KimiHookInstaller.swift` — read to confirm they are **out of scope** (different
  array shapes; see blast radius).
- `Sources/OpenIslandCore/OpenIslandHookMarkers.swift` — the marker atoms the
  leaves call (already shared, #42). Precedent for the shared-helper location.
- `.octospec/rules/installer-config-safety.md` — load-bearing rule (auto-injects
  via `Sources/OpenIslandCore/*HookInstaller.swift`), esp. "keep the gating split".

## Existing behavior
- **The Claude/Codex trio is duplicated verbatim.** `diff` of Claude L155-218 vs
  Codex L287-350 is empty — 64 identical lines. All three walk `groups: [Any]` →
  downcast each element to `[String: Any]` → read `group["hooks"] as? [Any]` →
  filter each hook via a **leaf predicate**, and:
  - `sanitize` / `sanitizeForInstall` are the *same* compactMap body; they differ
    ONLY in which leaf they invoke (`isManagedHook` vs `isManagedHookForInstall`).
    Both drop a group when its surviving hooks list is empty (partial-survival:
    non-managed hooks in the same group are kept).
  - `containsManagedHook` is a two-level `.contains` over the same shape using
    `isManagedHook`.
- **The leaf predicates diverge and are safety-critical** (they decide managed ⇒
  delete):
  - Claude `isManagedHook`: `command == managedCommand` OR
    `isLegacyOpenIslandHookCommand(command)` (marker + `--source claude`/bridge).
  - Codex `isManagedHook`: **statusMessage-first** (`== managedStatusMessage ||
    legacyManagedStatusMessage`), THEN `command == managedCommand`. No marker in
    the base predicate. `isManagedHookForInstall` adds the ungated legacy-marker
    fallback.
  - These are exactly what `installer-config-safety` says NOT to unify.
- **Callers:** Claude install L80/L89 (`sanitizeForInstall`), uninstall L123
  (`sanitize`), L125 (`containsManagedHook`); Codex install L104/L113, uninstall
  L139/L141. `containsManagedHook` feeds the `mutated` flag → `changed` /
  `managedHooksPresent` in the returned mutation.

## Contracts & blast radius
- **These functions decide which hooks get DELETED** from a user's
  `settings.json`. A behavior change risks dropping a user's non-managed hook or
  leaving a stale managed one. Behavior-neutrality is the whole game.
- The extraction target is the **array-walking mechanics only** — the part that is
  byte-identical and carries NO delete-vs-keep gating (the gating lives in the leaf
  closures, which stay per-installer).
- **Out of scope — genuinely different shapes:**
  - **Cursor** walks a *flat* `[[String: Any]]` entry list (1 level, no groups);
    filtering is inline (`CursorHookInstaller.swift:67,96`). No group nesting.
  - **Gemini** walks typed `[[String: Any]]` groups and does **whole-group
    replace** (removes the group if ANY hook matches, then re-adds a fresh managed
    group) — semantically different from Claude/Codex partial-survival
    (`GeminiHookInstaller.swift:60,88,136`).
  - **Kimi** is TOML line-walking (`stripManagedBlocks`), no dict arrays at all.
  - Folding any of these into the Claude-style helper would have to reconcile
    `[Any]` vs `[[String:Any]]`, 1-level vs 2-level, and partial-survival vs
    whole-group-replace — precisely the divergence the audit warns against.
- `containsClaudeIslandHook` (Claude L220-239, `claude-island-state.py` detection,
  3-level) is a *different* helper (a status flag, not a managed-hook mutator) —
  out of scope.

## Risks & unknowns
- **Codex sanitize-path test coverage is thin.** Claude has
  `claudeHookInstallationManagerRoundTripsInstallAndUninstall`
  (`ClaudeHooksTests.swift:29`); Codex's array-mutation coverage is indirect, via
  `SessionStateTests.swift` (install L939/L1015, uninstall L1074). The new slice
  should add direct tests for the shared walker so both leaves are exercised.
- **The two leaves must be passed as closures**, not merged. The safe shape is a
  shared enum (e.g. `HookGroupSanitizer`) with:
  `sanitize(groups: [Any], isManaged: ([String: Any]) -> Bool) -> [[String: Any]]`
  and `containsManagedHook(in: [Any], isManaged: ([String: Any]) -> Bool) -> Bool`.
  Each installer keeps its `isManagedHook`/`isManagedHookForInstall` and passes the
  right one — so `sanitize` and `sanitizeForInstall` both become call sites of the
  one shared `sanitize`, distinguished only by the closure.
- **N/A(test) risk:** the extraction is a pure mechanical relocation of identical
  code. Behavior-neutrality is provable by (a) byte-identical diff of the removed
  bodies vs the shared helper and (b) existing + new round-trip suites. But the
  shared helper itself is new code that SHOULD get a direct failing-first test
  (feed a mixed managed/non-managed group, assert partial survival + empty-group
  drop) — that IS a valid Red, so this slice is not a pure N/A(test) like the type
  relocations were.
- Decision for Plan: name of the shared type + whether to also route Claude's
  `containsClaudeIslandHook` through it (recommend NOT — different shape/purpose).
