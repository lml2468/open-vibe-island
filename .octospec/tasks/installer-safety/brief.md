---
type: Task
title: "Task: installer-safety"
description: Stop the installers from destroying user config — OpenCode malformed-config clobber, Cursor version-field clobber, and unbounded backup litter
tags: ["installer", "config", "safety", "data-loss", "correctness"]
timestamp: 2026-07-07T13:18:57Z
# --- octospec extension fields ---
slug: installer-safety
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-07T13:20:12Z
---

# Task: installer-safety

> Third slice of the `arch-quality-audit` discovery (see
> `.octospec/tasks/arch-quality-audit/discovery.md`, findings #7, #19, #20).
> Scoped to the **user-data-loss** bugs in the hook/plugin installers — the cases
> where Open Island silently damages a third-party tool's config. The larger
> installer de-duplication refactor (discovery #6) and multi-file transactionality
> (#21) are separate future slices; see Out of scope.

## Goal
The installers edit third-party config files (`~/.claude`, `~/.codex`,
`~/.cursor`, `~/.config/opencode`) and the project contract is that setup must be
**reversible and non-destructive**. Three paths violate that today. Fix each so a
user's existing config is never silently lost:

1. **OpenCode clobbers a malformed config (#7).**
   `OpenCodePluginInstallationManager.registerPluginInConfig`
   (`OpenCodePluginInstallationManager.swift:156-162`) does
   `if let … existing … { json = existing } else { json = [:] }`. If
   `config.json` exists but isn't decodable as a `[String: Any]` (invalid JSON,
   JSONC/comments, or a non-object root), it resets to `[:]` and writes back a
   file containing only its own `plugin` block — destroying the user's entire
   OpenCode config. Every other installer **throws** on a bad root
   (`ClaudeHookInstaller.swift:158`, `GeminiHookInstaller.swift`,
   `CursorHookInstaller.swift:129`); OpenCode alone clobbers. Make OpenCode throw
   a distinct error and abort (leaving the file untouched) instead of resetting —
   matching the other installers. `unregisterPluginFromConfig` (`:183-206`) uses
   `try?` and already aborts safely on a bad file; keep that behavior but ensure
   it never partially rewrites a file it couldn't fully parse.

2. **Cursor clobbers the user's top-level `version` (#19).**
   `CursorHookInstaller.installHooksJSON` (`CursorHookInstaller.swift:57`)
   unconditionally sets `rootObject["version"] = 1` on every install, overwriting
   any user-authored value; `uninstallHooksJSON` (`:111-113`) wipes the whole file
   to `[:]` when only `version` remains (`rootObject.count == 1`). Preserve a
   pre-existing `version`: only set the default `version` when the key is absent,
   and on uninstall do not delete a file that still carries user-authored
   top-level keys (only remove Open Island's managed `hooks`; leave the rest —
   including a `version` the user set — intact). A file that becomes genuinely
   empty of *all* content may still be removed.

3. **Unbounded, un-pruned backups (#20).** `backupFile(at:)` (duplicated in 7
   managers, e.g. `OpenCodePluginInstallationManager.swift:228`) writes
   `…​.backup.<iso8601>` on every changed write and never prunes. Driven by
   startup auto-install / repair loops, this accumulates unbounded backup files in
   the user's config dirs. Add bounded retention: keep at most the N most-recent
   Open-Island backups per target file (default N = 5) and delete older ones after
   a successful write. Because `backupFile` is copy-pasted, introduce a single
   shared helper (e.g. a `ConfigBackup` type in OpenIslandCore) and route the
   managers through it, so retention lives in one place. (This is a small, targeted
   dedup in service of the fix — NOT the full installer-abstraction refactor.)

## Background
- Installers use a "managed-hook marker + manifest + legacy-command fallback"
  scheme that makes uninstall reasonably idempotent; single-file writes are atomic
  (`.atomic`) with a backup taken first. The three bugs above are the exceptions
  to the otherwise-careful merge logic (discovery "bottom line").
- Verified on current `main` (post #17/#18): OpenCode reset at
  `OpenCodePluginInstallationManager.swift:161`; Cursor `version` at
  `CursorHookInstaller.swift:57` and wipe at `:111`; `backupFile` present in the
  7 managers listed in discovery #20 (H2).
- The pure hook-mutation logic (`*HookInstaller` enums) is already unit-tested per
  agent; those suites are the safety net to extend.
- No existing repo rule targets these files (`bridge-transport-invariants` and
  `session-state-invariants` are path-scoped elsewhere; `design-tokens-sync` is
  design-only). The global `security` rule applies (default-deny / don't destroy
  user data) via the `safety` framing.

## Load-bearing list
- **`OpenCodePluginInstallationManager.registerPluginInConfig` /
  `unregisterPluginFromConfig`** — the malformed-config branch and its atomic
  write; the OpenCode `config.json` round-trip.
- **`CursorHookInstaller.installHooksJSON` / `uninstallHooksJSON`** — the
  `version` set/wipe logic and the "file becomes empty" deletion condition;
  `CursorHookFileMutation.changed` semantics.
- **`backupFile(at:)` across the 7 managers** — Claude, Codex, Cursor, Gemini,
  Kimi, OpenCode, ClaudeStatusLine — behavior must stay identical except for the
  new retention; the shared helper must preserve the existing filename scheme so
  older backups (from prior versions) are still recognized/pruned.
- **Reversibility/idempotence contract** — install→uninstall must restore the
  user's file to (at least) a state that preserves their non-managed content;
  re-install must not accumulate managed entries.
- **Per-agent installer test suites** (`*HookInstallerTests` / manager tests) —
  the safety net; extend for the three fixes.

## Out of scope
- **Discovery #6** — the full installer de-duplication (a `HookInstaller`
  protocol / shared base folding the ~5-7 near-identical managers). This slice
  only extracts the one `backupFile`/retention helper needed for #20.
- **Discovery #21** — cross-file transactional install (config.toml + hooks.json +
  status-line scripts as one atomic group). Best built on the #6 abstraction;
  separate slice.
- **#22 TOML round-trip fragility**, **M7 JSON reformatting-on-write**, **M11
  status() off-main-thread** — related installer issues but distinct; not here.
- Any change to the hook *payload* models or the bridge.
- The Setup CLI surface gap (#L14).

## Acceptance
- **A1 — OpenCode never clobbers.** A test: given a `config.json` that exists but
  is not a decodable JSON object (e.g. `"not json"` or a JSON array), the install
  path **throws** a distinct error and leaves the original file byte-for-byte
  unchanged (assert file contents unchanged, no write). A valid config still gets
  the `plugin` entry added, preserving all other keys.
- **A2 — Cursor preserves `version`.** A test: given `~/.cursor/hooks.json` with
  `{"version": 3, ...user keys...}`, after install the top-level `version` is
  still `3` (not forced to `1`); when `version` is absent, install sets the
  default. After uninstall, a file that had user-authored top-level keys (incl. a
  user `version`) retains them and is **not** deleted; only the managed `hooks`
  are removed.
- **A3 — bounded backups.** A test drives >N changed writes against one target and
  asserts at most N (=5) Open-Island backup files remain, the newest ones. Backup
  content still equals the pre-write file.
- **A4 — shared backup helper.** `backupFile` logic lives in one shared type used
  by the managers (grep: the per-manager copies delegate to it); the timestamped
  filename scheme is unchanged so pre-existing backups are recognized.
- **A5 — reversibility preserved.** Existing installer test suites pass; an
  install→uninstall round-trip on a config that had unrelated user keys restores
  those keys (no net loss, no leftover managed entries).
- **A6 — gate green.** `zsh scripts/harness.sh ci` (`swift build` + `swift test`)
  passes; no new warnings.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
