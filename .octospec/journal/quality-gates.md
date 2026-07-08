---
type: Journal
title: "Journal: quality-gates"
description: Added enforcement — warnings-as-errors + SwiftLint in CI, guarded shipped PII, covered the fail-open contract
tags: ["ci", "build-config", "linter", "testability", "security"]
timestamp: 2026-07-08T02:44:56Z
slug: quality-gates
source: self
---

# Journal: quality-gates

Fourth implemented slice of the `arch-quality-audit` discovery (findings #26, #9,
#8). The enforcement layer — turns "asserted by inspection" quality properties
into machine-checked gates.

## What was done

1. **Warnings-as-errors (#26/#16).** Fixed the sole existing warning
   (`CodexSessionTrackingTests.swift` — the dead `initialSnapshot` became a real
   `#expect(initialSnapshot.phase == .running)`, strengthening the test), then
   threaded `-Xswiftc -warnings-as-errors` through the harness `build`/`test`
   steps. Chose the harness-flag approach over `Package.swift` `.unsafeFlags` so
   Xcode (`open Package.swift`) and `package-app.sh` are unaffected — the latter
   builds independently of the harness, so packaging can never be broken by the
   flag.
2. **SwiftLint (#26).** New `.swiftlint.yml` + `scripts/lint-swift.sh`, wired into
   `harness.sh lint` and `ci.yml` (CI installs SwiftLint and sets
   `OPEN_ISLAND_REQUIRE_SWIFTLINT=1`; locally it degrades gracefully if absent).
   ~180 default rules are active as a forward gate; a first draft surfaced 95
   violations (all test-code idioms — force-cast of decoded JSON, String<->Data
   conversions), so those specific rules are parked in the config with a note,
   rather than reformatting 95 sites (out of scope for r1). Current tree passes
   `swiftlint --strict` with 0 violations.
3. **Shipped PII (#9).** Replaced `/Users/wangruobing/Personal/` →
   `/Users/dev/Projects/` across `IslandDebugScenario.swift` (behavior-neutral
   display strings). A release `OpenIslandApp` binary now has zero personal-home
   paths (verified via `strings`).
4. **Fail-open contract test (#8).** New `HookFailOpenTests` pins that
   `BridgeCommandClient.send` against a dead socket throws (→ the CLI's `try?`
   yields nil → no directive → agent proceeds) and fails fast (well under the
   timeout).

## Verification

- All acceptance directly demonstrated: zero warnings; an injected warning makes
  the build exit 1 (removed → green); SwiftLint `--strict` = 0 violations;
  release binary has 0 PII hits; fail-open tests pass; `harness.sh ci` green
  (369 tests) and all release products build.
- SwiftLint was installed locally to verify the config against the real tree
  rather than guessing — that caught the 95-violation first draft.

## Learning

- **swift-tools 6.2 already enables Swift 6 complete-concurrency checking by
  default** — the audit's "no strict-concurrency flag" (#1 build-config) is a
  non-gap. This slice adds the *warnings* gate (which includes concurrency
  warnings), not a separate concurrency flag. Don't re-litigate that finding.
- **Verify a linter config against the real tree before shipping it.** A
  plausible-looking `.swiftlint.yml` failed 95 times on first run; only running
  the actual binary (with `DEVELOPER_DIR` pointing at Xcode, since SwiftLint needs
  `sourcekitd`) revealed which default rules this codebase's test idioms violate.
- **Prefer a build-flag gate over `Package.swift` `.unsafeFlags`** for
  warnings-as-errors — keeps the package consumable by Xcode/packaging while still
  gating CI. Captured as the `ci-quality-gates` rule.
