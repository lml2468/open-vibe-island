---
type: Note
title: "Discovery: manager-roundtrip-tests"
description: Add manager-level install→uninstall round-trip + status characterization tests for the 3 thin/untested hook installation managers (Gemini, Kimi, Codex) as the safety net for the ConfigManifestStore extraction
tags: ["discovery"]
timestamp: 2026-07-09T09:55:00Z
# --- octospec extension fields ---
slug: manager-roundtrip-tests
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — manager tier, safety-net slice)
source: self
---

# Discovery: manager-roundtrip-tests

> The **Discover** phase output. Read-only exploration done BEFORE the brief.
> Test-only slice: adds the manager-level regression net that makes the
> follow-on `ConfigManifestStore` extraction (blocked task) safe. It writes NO
> production code.

## Relevant files (test targets — read-only here)
- `Sources/OpenIslandCore/GeminiHookInstallationManager.swift` — **zero
  manager-level tests today**. `install(hooksBinaryURL:)`/`uninstall()`/
  `status(hooksBinaryURL:)`, JSON `settings.json`, returns
  `GeminiHookInstallationStatus`.
- `Sources/OpenIslandCore/KimiHookInstallationManager.swift` — **zero
  manager-level tests today**. Same API shape but **TOML** `config.toml` (String
  I/O), returns `KimiHookInstallationStatus`.
- `Sources/OpenIslandCore/CodexHookInstallationManager.swift` — **thin** (only an
  indirect use in `SessionStateTests.swift:1298`). The richest manager: writes
  **two** files (`config.toml` feature flag + `hooks.json`), has legacy-manifest
  cleanup + `resolvedManifestURL()`, an injectable `featureKeyProvider`, and a
  `featureFlagEnabled` status field.
- Test template: `Tests/OpenIslandCoreTests/CursorHooksTests.swift:208`
  (`cursorHookInstallationManagerRoundTripsInstallAndUninstall`) — the existing
  pattern: temp dir, fake binary with 0o755, install → assert managedHooksPresent
  + files exist, uninstall → assert cleared + manifest gone.
- Injection seams (all three): `<agent>Directory: URL`,
  `managedHooksBinaryURL: URL`, `fileManager: FileManager = .default` (+ Codex
  `featureKeyProvider`). Tests point the directory at a temp dir; no other seam
  needed (real FS under a temp root, as Cursor/Claude tests do).

## Existing behavior (what a round-trip test must pin)
- **Gemini** (`install`): create dir → read settings → install binary →
  `installSettingsJSON` → backup-if-changed+exists → write contents → write
  manifest (JSONEncoder iso8601 + prettyPrinted+sortedKeys) → `status`.
  `uninstall`: load manifest → `uninstallSettingsJSON(managedCommand:
  manifest?.hookCommand)` → backup → write-or-remove-if-nil → remove manifest →
  `status`. `status.managedHooksPresent` = `uninstallSettingsJSON(...).managedHooksPresent`.
- **Kimi**: same skeleton, but TOML String I/O; `installConfigTOML` is
  **non-throwing**; `status.managedHooksPresent` = `uninstallConfigTOML(...).changed`
  (note: `.changed`, not `.managedHooksPresent` — Kimi has no such field).
- **Codex**: two-file. `install`: `enableCodexHooksFeature(in: config,
  preferredKey:)` + `installHooksJSON` → backup each changed file → write
  config.toml (always) + hooks.json → manifest carries
  `enabledCodexHooksFeature` → remove legacy manifest → `status`. `uninstall`:
  `uninstallHooksJSON` → backup/write/remove hooks.json → **conditionally**
  `disableCodexHooksFeatureIfManaged` gated on `manifest.enabledCodexHooksFeature
  && !hooksMutation.hasRemainingHooks` → remove primary+legacy manifest →
  `status`. `status.featureFlagEnabled` = `isCodexHooksFeatureEnabled(in: config)`.
- Post-install invariants worth asserting: settings/hooks/config file exists;
  manifest file exists; `status.managedHooksPresent == true`; (Codex)
  `status.featureFlagEnabled == true` and config.toml contains the flag.
- Post-uninstall invariants: `status.managedHooksPresent == false`; manifest file
  removed; (Codex) feature flag disabled when no user hooks remained.

## Contracts & blast radius
- **These are characterization tests** — they encode CURRENT behavior and must
  pass on `origin/main` as-is (no production change in this slice). They become
  the regression net for slice A (`ConfigManifestStore`), which will relocate the
  `loadManifest` / manifest-encode-write / `resolvedHooksBinaryURL` / `backupFile`
  private helpers these managers share verbatim.
- Because slice A will rewrite exactly these managers' helper calls, the tests
  must exercise the **full manager round-trip through the real FS** (temp dir),
  not just the pure installer — the pure installers are already well covered; the
  gap is the manager orchestration (dir create, backup, atomic write, manifest
  read/write, status derivation).
- No behavior change, so no `installer-config-safety` gating is touched here; the
  rule still frames WHAT the tests should protect (backup-on-change, delete-only-
  when-empty, manifest lifecycle).

## Risks & unknowns
- **Kimi status field mismatch:** Kimi's `status.managedHooksPresent` derives from
  `uninstallConfigTOML(...).changed`, not a `managedHooksPresent` field — the test
  must assert the manager's Status value, not assume a mutation field name.
- **Codex feature-flag round-trip:** the most valuable Codex assertion is the
  gated `disableCodexHooksFeatureIfManaged` — install enables the flag, uninstall
  (with no surviving user hooks) disables it. A test that installs then uninstalls
  and asserts `featureFlagEnabled` goes true→false pins the two-file transaction
  that slice A must not disturb. Also worth a "user has their own hook" variant so
  uninstall keeps the flag (hasRemainingHooks true) — but that may be scope creep;
  keep the core round-trip + flag toggle, add the preserve-foreign case only if
  cheap.
- **Binary install seam:** `ManagedHooksBinary.install` copies the fake binary;
  tests must create an executable (0o755) fake at a `hooksBinaryURL`, as the
  Cursor test does, or `install` throws.
- No decision needed for a human — this is additive test coverage; the only Plan
  choice is how many variants per manager (recommend: 1 round-trip + 1 targeted
  characterization each; Codex gets the flag-toggle assertion).
