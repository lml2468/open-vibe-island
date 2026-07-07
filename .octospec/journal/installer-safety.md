---
type: Journal
title: "Journal: installer-safety"
description: Stopped the installers from destroying user config — OpenCode clobber, Cursor version clobber, unbounded backups
tags: ["installer", "config", "safety", "data-loss", "correctness"]
timestamp: 2026-07-07T13:28:47Z
slug: installer-safety
source: self
---

# Journal: installer-safety

Third implemented slice of the `arch-quality-audit` discovery (findings #7, #19,
#20). Independent branch off `main` after #17/#18 merged.

## What was done

Three user-data-loss bugs in the hook/plugin installers, plus a small shared
backup helper. The broader installer de-dup (#6) and multi-file transactionality
(#21) were deliberately deferred to their own slices.

1. **OpenCode clobber (#7)** — `registerPluginInConfig` used to reset a malformed
   `config.json` to `{}` and write back only its own `plugin` block, destroying
   the user's config. It now distinguishes "file absent" (start fresh) from "file
   present but unparseable" and throws the new
   `OpenCodePluginInstallerError.invalidConfigJSON`, leaving the file untouched —
   matching every other installer, which already threw.

2. **Cursor `version` clobber (#19)** — `installHooksJSON` force-set
   `version = 1` on every install; `uninstallHooksJSON` wiped the file to `{}`
   when only `version` remained. Install now sets the default only when `version`
   is absent (preserving a user value); uninstall removes only the managed
   `hooks` and no longer deletes a file that still carries user-authored keys. A
   residual `{ "version": 1 }` may remain after uninstall — harmless, and safer
   than risking a wipe of a version the user set.

3. **Unbounded backups (#20)** — the `backupFile` body was copy-pasted across
   seven managers and never pruned. Introduced `ConfigBackup` (OpenIslandCore)
   with bounded retention (keep the newest 5 per target), same timestamped
   filename scheme so older backups are still recognized/pruned. All seven
   managers now delegate to it. This is a targeted dedup in service of the fix,
   not the full installer-abstraction refactor.

## Verification

- New tests: `InstallerSafetyTests` (backup create/no-op/prune-to-limit, OpenCode
  throw-and-preserve, OpenCode preserve-valid-config) and four `CursorHooksTests`
  cases (preserve/default version, uninstall preserves user keys); updated
  `cursorHookInstallerUninstallsCleanly` for the intended residual-version
  behavior.
- Full gate green: `swift build` + `swift test` (367 tests, 45 suites) via
  `scripts/harness.sh ci`, exit 0, no new warnings.

## Learning

- **A config editor must never reset-on-parse-failure.** When a third-party
  config file exists but doesn't parse, throw and abort — never fall back to an
  empty object and write, which silently destroys the user's file. Absent file =
  start fresh; present-but-unparseable = refuse.
- **Preserve unknown top-level keys.** Only mutate the keys you own; on uninstall
  remove only your managed subtree and delete the file only when it is genuinely
  empty. If you can't prove a value is yours (e.g. a `version` you may or may not
  have added), keep it.
- **Any repeated backup/write needs bounded retention** — an unpruned
  timestamped-backup-on-every-write leaks files into the user's home over time.
- Captured as the load-bearing rule `installer-config-safety`.
