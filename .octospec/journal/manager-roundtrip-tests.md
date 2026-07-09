---
type: Journal
title: "Journal: manager-roundtrip-tests"
description: Added manager-level install→uninstall round-trip + status characterization tests for the three thinnest hook installation managers (Gemini/Kimi/Codex) as the regression net for the ConfigManifestStore extraction
tags: ["installer", "config", "test-coverage", "correctness"]
timestamp: 2026-07-09T11:05:00Z
slug: manager-roundtrip-tests
source: self
---

# Journal: manager-roundtrip-tests

Test-only safety-net slice of the `arch-quality-audit-r2` cluster-B manager tier.
See `.octospec/tasks/manager-roundtrip-tests/brief.md` (r1, approved). Precedes and
unblocks the `ConfigManifestStore` extraction (slice A).

## What was done

Added `HookInstallationManagerRoundTripTests` (3 tests) covering the three
thinnest-tested managers through the real filesystem (temp dir, fake 0o755 binary):
`GeminiHookInstallationManager` and `KimiHookInstallationManager` (both had **zero**
manager-level tests) and `CodexHookInstallationManager` (previously only indirect).
Each drives `install()` → asserts config file + manifest exist,
`status.managedHooksPresent == true`, and `manifest.hookCommand` matches the command
built from the installed binary; then `uninstall()` → asserts `managedHooksPresent
== false`, manifest removed, and the managed content is directly gone (Gemini
`settings.json` removed; Kimi marker comment absent; Codex `hooks.json` removed).
Codex additionally pins the two-file feature-flag transaction: `featureFlagEnabled`
toggles true→false across the round-trip (the gated `disableCodexHooksFeatureIfManaged`).
No production change.

## Verification

- All 3 tests pass on `origin/main` as written — they characterize current behavior
  (this is the point: no Red→Green for a pure-coverage slice).
- Independent Verify (fresh context) PASS — confirmed test-only scope (zero
  `Sources/**` diff), and audited each test for DISCRIMINATING assertions (the
  inverse-of-Red check): each would fail if the manager stopped writing/removing a
  file, the manifest, or (Codex) toggling the flag; each goes through the manager
  orchestration (dir-create, backup, atomic write, manifest read/write, status
  derivation), not the pure installer. Reviewer suggested optional hardening, which
  was folded in (manifest.hookCommand + direct cleanup assertions). Gate green:
  `harness.sh ci` (476 tests), exit 0.

## Learning

- **A characterization/safety-net slice inverts the TDD obligation, and that must be
  stated explicitly in the brief.** There is no Red step (the tests pass on main by
  design — they pin already-correct behavior), so the honest exemption is
  `N/A(test-first)` with the reason, and Verify's job shifts from "did the test fail
  first" to "is each assertion DISCRIMINATING" — would it fail if the code under
  test regressed? A green-on-main test that asserts nothing load-bearing is the
  characterization-slice equivalent of a tautological Red. The concrete guard: for
  each test ask "what regression in the NEXT slice would this catch?" — if the
  answer is "none", the assertion is worthless.
- **Sequence the safety net before the refactor when the refactor targets untested
  code.** The manager base-class idea was rejected as too divergent/risky; the
  *safe* extraction (`ConfigManifestStore`, shared private helpers) still rewrites
  the least-tested managers (Gemini/Kimi had zero manager-level tests). Landing the
  round-trip net as its own PR first means slice A is verifiable against real
  regression coverage instead of hoping the pure-installer suites catch an
  orchestration bug they never exercised.
- **Manager-orchestration coverage is a distinct layer from pure-installer coverage.**
  The pure `*HookInstaller` funcs were well tested, but the managers' dir-create →
  backup → atomic-write → manifest-lifecycle → status-derivation path was not — and
  that is exactly the config-delete surface a shared-helper extraction touches. Test
  through the manager (temp dir), not just the pure function.
- **Fresh worktrees need `Package.resolved` copied from the parent checkout to build
  offline** — it's gitignored (must not be committed), but SPM re-resolves against
  git remotes without it, which fails during a network blip. `cp
  ../..//Package.resolved .` unblocks. (Env quirk, not a code learning.)
