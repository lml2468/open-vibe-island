---
type: Journal
title: "Journal: dedup-installer-loadroot"
description: Deduped the 4 near-identical loadRootObject copies into shared JSONConfigSerialization, parameterizing the per-file error via @autoclosure; config-safety preserved
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T08:00:00Z
slug: dedup-installer-loadroot
source: self
---

# Journal: dedup-installer-loadroot

Seventeenth implemented slice of the `arch-quality-audit-r2` discovery — the second
cluster-B cut, extending the `JSONConfigSerialization` helper.

## What was done

The 4 JSON installers' `loadRootObject(from:)` were identical except the thrown
error type. Extracted a shared `JSONConfigSerialization.loadRootObject(from:invalidError:)`
that takes the per-file error via `@autoclosure`, and reduced each installer's copy
to a one-line delegate passing its own error (Claude→invalidSettingsJSON,
Codex/Cursor→invalidHooksJSON, Gemini→invalidSettingsJSON). Kimi (TOML) untouched.
The three-way behavior — nil→`[:]`, valid dict→dict, non-dict→throw — is preserved.

## Verification

- New `JSONConfigLoadRootTests` (4): nil→`[:]`; valid dict returned; non-dict array
  → throws the injected sentinel (asserting the throw AND its identity — no reset
  to `[:]`); malformed JSON throws.
- TDD trail: `red:` stubbed `loadRootObject` to return `[:]`, so the valid-dict /
  non-dict / malformed cases failed on assertion (nil→`[:]` passed as a guard);
  Green filled the impl + delegated (`git diff red..green -- Tests/` = 0 bytes).
- Config-safety preserved: nil→start-fresh, non-dict→throw (never overwrite), each
  caller keeps its own error. Existing installer round-trip suites pass unchanged.
- Independent Verify (fresh context) PASS, no findings — confirmed the @autoclosure
  is lazy (error only on the throw path), all 4 pass their OWN error (no swap), the
  parse-guard lives in one place. Gate green: `harness.sh ci` (456 tests), exit 0.

## Learning

- **`@autoclosure () -> Error` is the minimal seam for deduping code that differs
  only by the thrown error.** Each caller keeps its distinct error type with zero
  behavior change, and — critically — the closure is evaluated ONLY on the throw
  path, so constructing the error is never eager. Preferable to a generic
  `throws(E)` (more ceremony) or collapsing to one shared error (a behavior change
  — callers would throw a different type). The copy-paste hazard to guard at Verify
  is a delegate passing the WRONG error; check each line-by-line.
- **A "no reset-on-parse-failure" config-safety property must be pinned by a test
  that asserts the THROW, not merely a non-empty result.** The dangerous regression
  is silently returning `[:]` on non-dictionary input (which would overwrite the
  user's file); the test feeds a top-level JSON array and asserts the specific
  injected error is thrown — so a future "simplify" that swallows the error and
  returns `[:]` fails loudly. Captured against `installer-config-safety`.
- **Cluster B remaining is now the risky/structural tier:** the divergent
  command-detection predicates, the `sanitize`/hook-array mutators (the actual
  config-write surface), and the manager `status/install/uninstall` base-class
  extraction (needs a protocol with associated Status types). The two easy pure
  helpers (serialize, loadRootObject) are done.
