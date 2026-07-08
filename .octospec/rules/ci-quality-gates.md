---
type: Rule
title: CI quality gates
description: How this repo enforces build/lint quality — warnings-as-errors, SwiftLint, no shipped PII. Keep the gate green and don't weaken it.
tags: ["ci", "build-config", "linter", "security"]
timestamp: 2026-07-08T02:44:56Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: ci-quality-gates
tier: repo
priority: 80
load_bearing: false
inject_when:
  paths:
    - "Package.swift"
    - "scripts/harness.sh"
    - "scripts/lint-swift.sh"
    - ".swiftlint.yml"
    - ".github/workflows/ci.yml"
    - "Sources/OpenIslandApp/IslandDebugScenario.swift"
  touches: ["ci", "build-config", "linter"]
source: self
supersedes: []
---

# CI quality gates

The repo gates quality in `scripts/harness.sh ci` (run by `.github/workflows/ci.yml`).
When changing build/CI/lint config, keep these invariants.

## Warnings are errors

- `swift build` and `swift test` run with `-Xswiftc -warnings-as-errors` in the
  harness. Do not remove the flag. If a build warning appears, fix it — don't
  silence the gate. (swift-tools 6.2 already runs Swift 6 complete-concurrency
  checking, so concurrency issues surface as warnings → errors here.)
- Prefer the harness build-flag over `Package.swift` `.unsafeFlags`, which breaks
  Xcode `open Package.swift` and release packaging. `package-app.sh` builds
  independently of the harness, so it must stay warning-clean on its own too.

## SwiftLint

- `.swiftlint.yml` is calibrated so `swiftlint --strict` passes the current tree
  with 0 violations. CI installs SwiftLint and runs it with
  `OPEN_ISLAND_REQUIRE_SWIFTLINT=1`; `scripts/lint-swift.sh` degrades gracefully
  when the binary is absent locally.
- When you touch the config, **run `swiftlint --strict` against the real tree**
  (with `DEVELOPER_DIR` pointing at Xcode — SwiftLint needs `sourcekitd`) before
  committing; a plausible config can still fail dozens of times. Tighten rules by
  re-enabling parked ones and fixing the sites in a dedicated cleanup — never
  weaken a rule just to make a new violation pass.

## No shipped PII

- No personal home paths / usernames (`/Users/<name>/…`) in any target compiled
  into a release build. Debug/harness fixtures use neutral placeholders
  (`/Users/dev/Projects/…`). A release build must contain no personal paths
  (checkable via `strings`).

## Fail-open stays tested

- The hook fail-open contract (bridge down → agent unaffected) has a test
  (`HookFailOpenTests`). Don't remove it; extend it if the hook entry paths change.
  See [[bridge-transport-invariants]] for the transport-side contract.
