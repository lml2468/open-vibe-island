---
type: Rule
title: Installer config-file safety
description: Rules for editing third-party config files in the hook/plugin installers — never clobber, preserve unknown keys, bounded backups.
tags: ["installer", "config", "safety", "data-loss"]
timestamp: 2026-07-07T13:28:47Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: installer-config-safety
tier: repo
priority: 85
load_bearing: true
inject_when:
  paths:
    - "Sources/OpenIslandCore/*HookInstaller.swift"
    - "Sources/OpenIslandCore/*HookInstallationManager.swift"
    - "Sources/OpenIslandCore/OpenCodePluginInstallationManager.swift"
    - "Sources/OpenIslandCore/ClaudeStatusLineInstallationManager.swift"
    - "Sources/OpenIslandCore/ConfigBackup.swift"
    - "Sources/OpenIslandSetup/OpenIslandSetupCLI.swift"
  touches: ["installer", "config"]
source: self
supersedes: []
---

# Installer config-file safety

The installers edit third-party config files the user owns (`~/.claude`,
`~/.codex`, `~/.cursor`, `~/.config/opencode`, …). Setup must be reversible and
non-destructive. When changing installer code, keep these invariants.

## Never reset-on-parse-failure

- If a config file exists but does not parse (invalid JSON/TOML, wrong root
  type), **throw and abort** — leave the file untouched. Never fall back to an
  empty object / default and write it back; that silently destroys the user's
  config.
- Distinguish the two cases explicitly: **absent file** → start fresh is fine;
  **present-but-unparseable** → refuse. (`OpenCodePluginInstallationManager`
  regressed on this — it now throws `invalidConfigJSON`.)

## Preserve keys you don't own

- Only mutate the keys/subtree Open Island manages (its `hooks`, `plugin`
  entries, managed markers). Merge into the existing object; do not rewrite the
  whole file from a template.
- Do not force-overwrite a top-level field the user may have authored (e.g.
  Cursor's `version`): set a default only when the key is absent.
- On uninstall, remove only the managed subtree. Delete the file only when it is
  **genuinely empty** of all keys — never when unrelated user keys remain. If you
  can't prove a residual value is yours, keep it.

## Centralize marker literals, keep the gating split

- The brand-alias substrings that identify an Open Island / Vibe Island managed
  hook (`openislandhooks`/`vibeislandhooks`, `open-island-bridge`/`vibe-island-bridge`)
  live in **one** place — `OpenIslandHookMarkers.hasHooksMarker/hasBridgeMarker`.
  Never re-inline them in a predicate. A past brand rename already proved these
  drift: a missed site is a silent config-safety bug (a managed hook stops being
  recognized and survives uninstall, or a user's own hook gets matched and deleted).
- Do **not** unify the per-agent detection predicates themselves. Their gating
  genuinely diverges (Claude: `--source claude` for hooks, bare `claude` for bridge;
  Codex: ungated; Cursor/Gemini: bare agent-name, hooks-only; Kimi: `--source kimi`
  over both) and each drives a delete-vs-keep decision. Centralize the drift-prone
  *literals*; keep the safety-critical *gating* split and locally auditable.
- Pin each predicate's truth table with a **direct** test (relax `private`→`internal`
  if needed) so a future edit to a predicate is caught even when the higher-level
  installer round-trip suites don't exercise that exact marker/gate combination.
- When two installers share **byte-identical hook-array traversal** but a divergent
  managed-vs-user decision (as Claude and Codex did), extract the traversal into a
  shared helper (`HookGroupSanitizer`) that takes the leaf predicate as a
  `([String: Any]) -> Bool` **closure** — do NOT inline the gating into the shared
  walk. Each installer keeps its own `isManagedHook`/`isManagedHookForInstall` and
  passes it in. The traversal must be a *byte-equivalent* relocation (partial
  survival, drop-empty-group, drop non-dict, two-level contains). The hazard to
  check at Verify is a **swapped closure** (a delegate passing the wrong leaf, e.g.
  `sanitize` passing the install-time leaf) — check each delegate line-by-line.
- When installation managers share manifest persistence that differs **only by the
  Codable manifest type**, extract it into a generic shared store (`ConfigManifestStore`
  — `load<M: Decodable>`, `write<M: Encodable>`) rather than a base class. The
  extraction must reproduce the persistence contract EXACTLY: `.iso8601` decode/encode,
  `[.prettyPrinted, .sortedKeys]` output, `.atomic` write, and **nil-for-missing but
  throw-for-corrupt** on load (never reset — this is the manifest-lifecycle form of
  the parse-failure rule above). The hazard to check at Verify is a **strategy drift**
  (a decoder losing `.iso8601`, an encoder dropping `.sortedKeys`, a write losing
  `.atomic`) — byte-diff the extracted body against an original, not just the call sites.
- Do NOT extract everything that looks duplicated: a 1-line delegate (e.g. `backupFile`
  → `ConfigBackup`) or a helper with 2 callers that would need a wider signature (e.g.
  Claude/Codex-only `resolvedManifestURL`) is better left inline — extracting trades
  real dedup for indirection or a wider surface. Record such non-goals explicitly in
  the brief so Verify doesn't flag them as misses. Manager install/uninstall/status
  **orchestration stays per-manager** (blast-radius isolation); no base class/protocol.

## Bounded, atomic writes

- Back up before a changed write, and **bound retention** — keep at most N
  most-recent backups per target (see `ConfigBackup`), or timestamped backups
  accumulate unbounded in the user's home. Route all backups through the shared
  helper; don't re-implement the copy/prune logic per manager.
- Single-file writes stay atomic (`.atomic`). (Cross-file transactional installs
  are a separate, still-open concern — discovery #21.)
