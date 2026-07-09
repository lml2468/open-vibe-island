---
type: Journal
title: "Journal: dedup-sanitize-mutators"
description: Extracted the byte-identical Claude/Codex group→hooks array walkers into a shared closure-parameterized HookGroupSanitizer; kept each installer's divergent leaf predicate split so the config-delete gating stays locally auditable
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T09:45:00Z
slug: dedup-sanitize-mutators
source: self
---

# Journal: dedup-sanitize-mutators

Nineteenth implemented slice of the `arch-quality-audit-r2` discovery — the fourth
cluster-B cut and the first to touch the actual config-write (delete-driving)
surface. See `.octospec/tasks/dedup-sanitize-mutators/brief.md` (r1, approved).

## What was done

`ClaudeHookInstaller` and `CodexHookInstaller` carried byte-identical copies of the
three group→hooks array walkers (`sanitize`, `sanitizeForInstall`,
`containsManagedHook` — `diff` of the bodies was empty). Extracted the mechanical
walk into a shared `HookGroupSanitizer` enum whose two funcs take the leaf predicate
as a `([String: Any]) -> Bool` closure. Both installers now delegate one-liners,
each passing its OWN leaf: `sanitize`→`isManagedHook`,
`sanitizeForInstall`→`isManagedHookForInstall`, `containsManagedHook`→`isManagedHook`.
So `sanitize` and `sanitizeForInstall` collapse to call sites of the one shared
`sanitize`, distinguished only by the closure. The divergent, safety-critical leaves
(Claude marker/`--source claude`; Codex statusMessage-first) stay per-installer and
unchanged. Cursor (flat), Gemini (whole-group-replace), Kimi (TOML) left untouched —
genuinely different shapes.

## Verification

- New `HookGroupSanitizerTests` (10): A1 sanitize walk (partial survival + `matcher`
  preserved, drop-all-managed group, drop non-dict/no-hooks, keep full-user group),
  A2 two-level contains (true/all-user-false/malformed-false), A3 installer
  round-trips exercising each divergent leaf (Claude legacy-marker deletion keeps
  foreign; Codex statusMessage-managed-with-FOREIGN-command still deleted — the
  distinguishing Codex behavior; Claude install→uninstall → nil).
- TDD trail: `red:` (355b2fe) stubbed `HookGroupSanitizer` to `[]`/`false` → A1/A2
  positives failed on ASSERTION while A3 characterization tests passed against the
  unchanged inline walkers; Green (473d7d5) implemented the helper + delegated;
  `git diff red..green -- Tests/` = 0 bytes. (A Red iteration fixed two crash-on-
  index tests → guarded `.first`, and a wrong Codex event name `PreToolUse`→`Stop`
  since Codex only walks its own eventSpecs — both fixed before committing Red.)
- Independent Verify (fresh context) PASS, no findings — reviewer re-ran the red tree
  to confirm the assertion-failures, byte-diffed the shared helper against the
  original walkers (only substitution: leaf call → closure), confirmed correct
  per-installer closure delegation, leaves + `containsClaudeIslandHook` unchanged,
  Cursor/Gemini/Kimi + managers untouched. Gate green: `harness.sh ci` (473 tests),
  exit 0.

## Learning

- **When two files carry byte-identical logic that wraps a divergent decision,
  extract the wrapper and inject the decision as a closure.** Here the array
  traversal was identical between Claude and Codex, but the leaf (is-this-hook-managed)
  diverges and is the safety-critical part. A `([String:Any]) -> Bool` closure param
  lets the mechanical walk be shared once while each caller keeps its own gating
  inline and locally auditable — satisfying `installer-config-safety`'s "keep the
  gating split" without paying for 64 duplicated lines. The copy-paste hazard to
  guard at Verify is a **swapped closure** (e.g. `sanitize` accidentally passing the
  install-time leaf); check each delegate line passes the leaf its original body used.
- **A round-trip characterization test (A3) that must pass at Red has to use inputs
  the code actually visits.** Two Red mistakes here were self-inflicted: an index
  crash (`result[0]` on the empty stub — a crash is not a valid assertion-Red; guard
  with `.first`) and using `PreToolUse` for the Codex case when Codex's uninstall
  only walks its own `eventSpecs` (SessionStart/UserPromptSubmit/PermissionRequest/
  Stop). The fix is to read the callee's iteration set before authoring the fixture —
  a "passing" characterization test that silently never touches the hook proves
  nothing.
- **Cluster B remaining is now just the structural manager tier:** the
  `*HookInstallationManager` `status/install/uninstall` base-class extraction (needs a
  protocol with associated Status/Mutation types). All the pure mechanical dedups
  (serialize, loadRootObject, hook markers, group-hook walkers) are done. The
  per-agent leaf predicates and the shape-divergent Cursor/Gemini/Kimi walkers are
  deliberately NOT dedup targets.
