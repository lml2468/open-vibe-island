---
type: Task
title: "Task: manager-roundtrip-tests"
description: Add manager-level install→uninstall round-trip + status characterization tests for the Gemini, Kimi, and Codex hook installation managers as the regression net for the ConfigManifestStore extraction
tags: ["installer", "config", "test-coverage", "correctness"]
timestamp: 2026-07-09T09:58:00Z
# --- octospec extension fields ---
slug: manager-roundtrip-tests
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — manager tier, safety-net slice)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T10:47:25Z
---

# Task: manager-roundtrip-tests

> Safety-net slice preceding `ConfigManifestStore` (slice A, blocked on this).
> **Test-only**: adds the missing manager-level regression coverage for the three
> thinnest managers so the follow-on helper extraction is verifiable against a
> real net. Independent branch off `origin/main`. See
> `.octospec/tasks/manager-roundtrip-tests/discovery.md`.

## Goal

The `GeminiHookInstallationManager` and `KimiHookInstallationManager` have **zero**
manager-level tests; `CodexHookInstallationManager` has only indirect coverage.
These three managers share the exact private helpers (`loadManifest`, the
manifest encode-and-write block, `resolvedHooksBinaryURL`, `backupFile`) that the
next slice (`ConfigManifestStore`) will relocate — so today that extraction would
rewrite the least-tested code in the cluster.

Add manager-level **install→uninstall round-trip + status** characterization tests
for all three, exercising the full orchestration through the real filesystem
(temp dir), following the existing
`cursorHookInstallationManagerRoundTripsInstallAndUninstall` pattern
(`CursorHooksTests.swift:208`). The tests pin current behavior: post-install the
config file + manifest exist and `status.managedHooksPresent == true`;
post-uninstall the manifest is gone and `managedHooksPresent == false`; and for
Codex the two-file feature-flag transaction toggles `featureFlagEnabled`
true→false across the round-trip.

## Not a Red→Green slice (why)

This is **additive test coverage of already-correct behavior**, not a behavior
change. Characterization tests encode what the managers do TODAY and therefore
**pass on `origin/main` as written** — there is no production code to make fail
first, so the TDD Red step does not apply. The honesty obligation here is the
inverse of Red: each test must be shown to genuinely EXERCISE the manager (not
tautologically pass), and must be one that would BREAK if slice A's extraction
changed behavior. The value is realized in slice A, where these become the net.
(Per the workflow: a pure-coverage item is marked `N/A(test-first)` with this
reason; the Verify still confirms the tests encode real, discriminating
assertions.)

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`GeminiHookInstallationManager`** — new round-trip + status test. `[installer] [config]`
- **`KimiHookInstallationManager`** — new round-trip + status test; note TOML
  String I/O and that `status.managedHooksPresent` derives from
  `uninstallConfigTOML(...).changed`. `[installer] [config]`
- **`CodexHookInstallationManager`** — new round-trip + status test incl. the
  `featureFlagEnabled` true→false toggle across install/uninstall (the two-file
  feature-flag transaction). `[installer] [config]`
- **The tests only** — NO production change in this slice.

## Out of scope
- **Any production code change.** This slice adds tests exclusively; if writing a
  test reveals a real bug, that is a separate slice (do not fix it here — a
  characterization test pins current behavior, even if surprising).
- **The `ConfigManifestStore` extraction itself** — the next slice (blocked on
  this net).
- Claude/Cursor managers (already have round-trip tests); OpenCode &
  ClaudeStatusLine managers (outliers, out of the manager-dedup cluster).
- New injection seams / refactoring the managers for testability — they are
  already injectable via directory + fileManager; use that.

## Acceptance
<!-- Test-only slice: items are the coverage that must exist and pass on main. -->
- **A1 — Gemini manager round-trip.** A test installs via
  `GeminiHookInstallationManager.install(hooksBinaryURL:)` into a temp `.gemini`
  dir (fake 0o755 binary), asserts `settings.json` + manifest exist and
  `status.managedHooksPresent == true` with the expected managed hook groups
  present; then `uninstall()` and asserts `managedHooksPresent == false`, manifest
  removed. *(Passes on main — characterizes current behavior.)*
- **A2 — Kimi manager round-trip.** Same shape against `config.toml` (TOML);
  asserts post-install `config.toml` + manifest exist and
  `status.managedHooksPresent == true` (derived from `uninstallConfigTOML.changed`),
  and a managed `[[hooks]]` block is present; post-uninstall cleared + manifest
  gone. *(Passes on main.)*
- **A3 — Codex manager round-trip + feature-flag toggle.** Installs (two files:
  `config.toml` + `hooks.json`), asserts both files + manifest exist,
  `status.featureFlagEnabled == true`, `status.managedHooksPresent == true`; then
  `uninstall()` (no surviving user hooks) and asserts `featureFlagEnabled == false`
  (the gated `disableCodexHooksFeatureIfManaged` fired), `managedHooksPresent ==
  false`, manifest(s) removed. *(Passes on main; pins the two-file transaction.)*
- **A4 — tests are discriminating + gate green.** Each test makes assertions that
  would FAIL if the manager stopped writing/removing the file, the manifest, or
  (Codex) toggling the flag — i.e. they are not tautological. `swift build` +
  `swift test` pass under the repo gate (warnings-as-errors + `swiftlint --strict`)
  with the new tests included. *(N/A(test-first): coverage-only slice; the Verify
  confirms the assertions are real and discriminating rather than a failing-first
  trail.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
