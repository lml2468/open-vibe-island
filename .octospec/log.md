# octospec log

Dated, one-line entries for octospec task activity in this repo. Newest first.

- 2026-07-07 — **installer-safety** (Finish): stopped the installers from
  destroying user config — OpenCode no longer clobbers a malformed `config.json`,
  Cursor preserves a user-authored top-level `version`, and backups are bounded
  (newest 5) via a shared `ConfigBackup` helper the 7 managers delegate to. Third
  slice of `arch-quality-audit`. Gate green (367 tests). Journal:
  `.octospec/journal/installer-safety.md`.
- 2026-07-07 — **reducer-purity** (Finish): made `SessionState` deterministic
  (injectable clock on `dismissSession`) and fixed two state-machine bugs —
  `answerQuestion` end-guard (no phantom resurrection) and `markProcessLiveness`
  stale-count reset. Second slice of `arch-quality-audit`. Gate green (349 tests).
  Journal: `.octospec/journal/reducer-purity.md`.
- 2026-07-07 — **bridge-security** (Finish): hardened the local bridge — write
  timeout (DoS/head-of-line-blocking fix), same-user socket auth + `0600`
  permissions, forward-compatible event decoding. First slice of
  `arch-quality-audit`. Gate green (355 tests). Journal:
  `.octospec/journal/bridge-security.md`.
