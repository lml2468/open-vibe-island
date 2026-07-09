---
type: Journal
title: "Journal: dedup-installer-serialize"
description: Extracted the 4 byte-identical JSON serialize(_:) copies in the hook installers into a shared, unit-tested JSONConfigSerialization helper
tags: ["dedup", "installer", "config", "maintainability"]
timestamp: 2026-07-09T07:30:00Z
slug: dedup-installer-serialize
source: self
---

# Journal: dedup-installer-serialize

Sixteenth implemented slice of the `arch-quality-audit-r2` discovery — the first
cut of finding #9 **cluster B** (hook-installer boilerplate), opening the cluster
the same way cluster A opened: smallest safe pure helper first.

## What was done

The 4 JSON-config installers (Claude/Codex/Cursor/Gemini) each carried a
byte-identical private `serialize(_:)` (`JSONSerialization.data(..., options:
[.prettyPrinted, .sortedKeys])`). Extracted into
`JSONConfigSerialization.serialize(_:)` (new OpenIslandCore file), deleted the 4
copies, routed all 8 call sites through it. Kimi (TOML) has no `serialize` and is
untouched. The escaping-adjacent `ClaudeStatusLineInstallationManager.serializeSettings`
is a different method, also untouched.

## Verification

- New `JSONConfigSerializationTests` (3): sorted-keys ordering + pretty-print,
  round-trip, and the empty-dict `"{\n\n}"` form.
- TDD trail: `red:` stubbed `serialize` to empty `Data()`, so all 3 failed on
  assertion; Green filled the one-liner + delegated (`git diff red..green --
  Tests/` = 0 bytes).
- Behavior-neutral: options unchanged → on-disk bytes identical → the existing
  installer suites (`ClaudeHooksTests`/`CursorHooksTests`/`GeminiHooksTests` +
  Codex), which decode the written config, pass unchanged.
- Independent Verify (fresh context) PASS, no findings — confirmed byte-equivalent
  options and that config parse/reset/backup logic is untouched. Gate green:
  `harness.sh ci` (452 tests) under warnings-as-errors + `swiftlint --strict`,
  exit 0.

## Learning

- **For a config-writing dedup, byte-identical option preservation IS the safety
  proof.** `installer-config-safety` depends on deterministic output
  (`.sortedKeys`) so a re-serialize doesn't spuriously look "changed" and trigger a
  backup, and doesn't reorder the user's keys. Extracting the serializer is safe
  precisely because the `options` array is preserved exactly — a changed/added
  option would be a silent behavior change. The neutrality proof is the identical
  options + the callers' existing content-asserting tests, not just "it compiles."
- **Cluster B, like cluster A, is a sequence — lead with the pure helpers, defer
  the structural risk.** Order: (1) `serialize` (this slice — byte-identical,
  pure, testable); (2) `loadRootObject` (identical except the per-file error type →
  parameterize the error; still pure/testable; must keep throw-on-non-dict +
  nil→`[:]` for config-safety); then defer the divergent command-detection
  predicates, the `sanitize`/hook-array mutators (the risky config-write surface),
  and the manager `status/install/uninstall` base-class extraction (needs a
  protocol with associated Status types). Don't bundle the structural rewrite into
  a "dedup." Captured against the `installer-config-safety` rule.
