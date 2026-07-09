---
type: Task
title: "Task: dedup-sanitize-mutators"
description: Extract the byte-identical Claude/Codex hook-array walkers (sanitize / sanitizeForInstall / containsManagedHook) into a shared closure-parameterized HookGroupSanitizer; keep each installer's divergent leaf predicate split
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T09:25:00Z
# --- octospec extension fields ---
slug: dedup-sanitize-mutators
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — fourth cut)
source: self
revision: 1
approvals: []
---

# Task: dedup-sanitize-mutators

> Nineteenth slice of the `arch-quality-audit-r2` discovery — the fourth cluster-B
> cut and the first to touch the actual config-write (delete-driving) surface.
> Independent branch off `origin/main`. See
> `.octospec/tasks/dedup-sanitize-mutators/discovery.md`.

## Goal

`ClaudeHookInstaller` and `CodexHookInstaller` carry **byte-identical** copies of
the three group→hooks array walkers (`diff` of Claude L155-218 vs Codex L287-350 is
empty — 64 duplicated lines):
- `sanitize(groups:managedCommand:)` — filters managed hooks out of each group,
  drops a group when its surviving hooks are empty (partial survival).
- `sanitizeForInstall(groups:replacingCommand:)` — the *same* body, differing only
  in which leaf predicate it calls.
- `containsManagedHook(in:managedCommand:)` — two-level `.contains`.

Extract the walking mechanics into a shared `HookGroupSanitizer` (new OpenIslandCore
enum) that takes the **leaf predicate as a closure**:
```
static func sanitize(groups: [Any], isManaged: ([String: Any]) -> Bool) -> [[String: Any]]
static func containsManagedHook(in groups: [Any], isManaged: ([String: Any]) -> Bool) -> Bool
```
Each installer keeps its own `isManagedHook` / `isManagedHookForInstall` leaf and
passes the right one — so both `sanitize` and `sanitizeForInstall` collapse to call
sites of the one shared `sanitize`, distinguished only by the closure. This removes
the 64-line duplication while moving **only the array-walking mechanics** — which
carry no delete-vs-keep gating.

**Deliberately NOT touching the leaf predicates.** Claude's leaf is marker/`--source
claude`-based; Codex's is statusMessage-first then command-equality. They genuinely
diverge and each decides which hooks get **deleted** during sanitize/uninstall, so
`installer-config-safety` requires keeping them split and locally auditable. Only the
identical mechanical walker moves; the gating stays per-installer via the closure.

## Background

- The walkers are pure and identical; the only reason they weren't shared already is
  historical copy-paste. The extraction mirrors the `JSONConfigSerialization` /
  `OpenIslandHookMarkers` shared-helper precedent (cluster B slices #40/#41/#42).
- **Injected rule:** `installer-config-safety` (load-bearing). The gating that
  decides managed-vs-user hooks is unchanged (it lives in the per-installer leaves);
  only the identical array-walking mechanics move into the shared helper.
- Codex's sanitize path is thinly tested today (indirect via `SessionStateTests`);
  the new direct helper tests close that gap for both leaves.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `HookGroupSanitizer`** — the shared closure-parameterized walkers. Its
  `sanitize` must reproduce the exact partial-survival + drop-empty-group semantics;
  `containsManagedHook` the exact two-level contains. `[installer] [config]`
- **`ClaudeHookInstaller` walkers** (`sanitize`/`sanitizeForInstall`/
  `containsManagedHook`, L155-218) — replaced by delegating one-liners passing the
  Claude leaves; leaf predicates + all callers unchanged. `[installer] [config]`
- **`CodexHookInstaller` walkers** (L287-350) — same delegation, passing the Codex
  (statusMessage-first) leaves; leaf predicates unchanged. `[installer] [config]`
- **The install/uninstall flows** that call these walkers — unchanged behavior
  (which hooks are treated as managed / deleted, and the `changed`/
  `managedHooksPresent` flags derived from `containsManagedHook`). `[installer] [config]`

## Out of scope
- **Cursor** (flat 1-level entry list), **Gemini** (whole-group-replace, not
  partial-survival), **Kimi** (TOML line-walking) — genuinely different array
  shapes; folding them in would reconcile the exact divergence the audit warns
  against. Left as-is.
- **The leaf predicates** (`isManagedHook`/`isManagedHookForInstall` in both, and
  the `isLegacy…`/statusMessage gating) — stay per-installer and unchanged.
- **`containsClaudeIslandHook`** (`claude-island-state.py`, 3-level status flag) —
  different shape and purpose; not touched.
- The **manager base-class** extraction (`*HookInstallationManager`) — a separate,
  later cluster-B slice.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `HookGroupSanitizer.sanitize` reproduces the partial-survival walk.** Given
  a `[Any]` of groups where a group has both a managed and a non-managed hook (per
  the injected `isManaged` closure), the managed hook is removed and the non-managed
  hook + the group are kept; a group whose hooks ALL match is dropped entirely; a
  non-dict element is dropped; a group with no `hooks` key is dropped (empty →
  drop). *(Testable: direct unit test with a stub `isManaged` closure. Fails first —
  the helper does not exist.)*
- **A2 — `HookGroupSanitizer.containsManagedHook` reproduces the two-level
  contains.** True iff some group has some hook for which the `isManaged` closure
  returns true; false for empty groups / non-dict elements / groups without a
  managed hook. *(Testable: direct unit test with a stub closure. Fails first.)*
- **A3 — Claude & Codex delegate with their own leaves, behavior preserved.** After
  the swap, `ClaudeHookInstaller` and `CodexHookInstaller` no longer define their own
  `sanitize`/`sanitizeForInstall`/`containsManagedHook` bodies (they call
  `HookGroupSanitizer`, passing `isManagedHook`/`isManagedHookForInstall`); their
  install/uninstall round-trips produce byte-identical output to `origin/main`. In
  particular Codex's statusMessage-first leaf still drives deletion (a hook with a
  managed `statusMessage` but a foreign command is still removed on uninstall).
  *(Testable: install→uninstall round-trip tests for both installers, incl. a Codex
  statusMessage-only managed hook and a Claude legacy-marker hook.)*
- **A4 — behavior neutral + gate green.** Existing installer suites
  (`ClaudeHooksTests` + the Codex coverage in `SessionStateTests`, Cursor/Gemini/Kimi
  untouched) pass unchanged; the removed Claude/Codex walker bodies are byte-equal to
  the shared helper's body (proven by the independent Verify's diff); `swift build` +
  `swift test` pass under the repo gate (warnings-as-errors + `swiftlint --strict`).
  *(N/A(test): the gate + existing suites are the behavior-neutral proof for the
  relocation; A1-A3 are the new positive tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
