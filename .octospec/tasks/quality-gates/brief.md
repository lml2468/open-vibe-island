---
type: Task
title: "Task: quality-gates"
description: Add enforcement — warnings-as-errors + SwiftLint in CI, guard shipped developer PII, and cover the fail-open contract with a test
tags: ["ci", "build-config", "linter", "testability", "code-smell", "security"]
timestamp: 2026-07-08T01:42:12Z
# --- octospec extension fields ---
slug: quality-gates
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-08T02:34:59Z
---

# Task: quality-gates

> Fourth slice of the `arch-quality-audit` discovery (see
> `.octospec/tasks/arch-quality-audit/discovery.md`, findings #26, #9, #8). This
> is the **enforcement layer** — it makes the quality properties the prior slices
> established (and future ones need) machine-checked in CI, and closes the two
> highest-value gaps the audit flagged as "verified by inspection only". Scoped
> deliberately narrow; see Out of scope.

## Goal
Turn three "asserted by inspection" quality properties into gates/coverage,
without a large refactor:

1. **Warnings-as-errors build gate (#26).** The build has no
   `-warnings-as-errors`, so warnings accumulate silently (the audit's #16 CI
   note). A full clean build today is warning-clean **except one**: an unused
   `initialSnapshot` in `CodexSessionTrackingTests.swift:695`. Fix that one
   warning, then make the repo build treat warnings as errors so new ones can't
   land. Apply it in a way that fails CI on any Swift warning (via
   `Package.swift` `swiftSettings` `.unsafeFlags(["-warnings-as-errors"])` on the
   targets, or an equivalent flag threaded through `scripts/harness.sh`). If
   `.unsafeFlags` proves incompatible with how the app target is consumed
   (Xcode/package-app), fall back to passing the flag in the harness `build`/`test`
   steps — whichever keeps both `swift build` and `package-app.sh` green.

2. **SwiftLint in CI (#26).** There is no Swift linter (`.swiftlint.yml` absent);
   the only "lint" is `lint-strings.sh`. Add a SwiftLint config tuned to the
   existing code (start lenient — enable a small, high-signal rule set and set
   sane thresholds so the current tree passes) and wire it into
   `scripts/harness.sh lint` + `.github/workflows/ci.yml`, installing SwiftLint in
   CI. The bar for revision 1: **the current tree passes** with a curated rule set
   (no mass churn); the value is preventing new violations, not reformatting the
   codebase now.

3. **Guard shipped developer PII (#9).** `IslandDebugScenario.swift` embeds
   `/Users/wangruobing/Personal/...` in ~9 string literals compiled into the app
   target. It is env-gated from the UI (`OPEN_ISLAND_HARNESS_SCENARIO`) but still
   ships in the release binary. Wrap the debug-scenario data (and its only
   consumers in `HarnessLaunchConfiguration`) in `#if DEBUG` so the literals are
   not compiled into release builds, OR replace the hardcoded personal paths with
   neutral placeholders (e.g. `~/Projects/example`). Release builds must contain
   no personal home paths; the harness/debug scenarios must still work in debug.

4. **Fail-open contract test (#8).** The hook CLI's fail-open invariant
   (`OpenIslandHooksCLI.swift` — bridge down → agent runs unchanged, no error to
   the agent) has **zero** tests. Add a test that exercises the CLI (or its
   core send path) with **no bridge listening** and asserts it exits without
   emitting a blocking/error directive — i.e. the agent is not blocked. Use a
   unique, non-existent socket path so no real bridge is contacted.

## Background
- swift-tools is **6.2**, so the package already builds under Swift 6 language
  mode with **complete concurrency checking on by default** — the audit's "no
  strict-concurrency flag" (#1 build-config) is effectively already satisfied by
  the language mode; this slice does not add a separate concurrency flag, it adds
  the *warnings* gate (which includes concurrency warnings). Note this in the
  journal so a future reader doesn't re-litigate it.
- Verified: full clean `swift build --build-tests` emits exactly one real warning
  (`CodexSessionTrackingTests.swift:695`); `swiftlint`/`swiftformat` not installed;
  no `.swiftlint.yml`; no test references fail-open.
- CI: `.github/workflows/ci.yml` runs `zsh scripts/harness.sh ci`
  (lint → docs → test → build) on `macos-26`, plus `package-verify`
  (`package-app.sh`). `harness.sh` `ci` = `lint`, `docs`(?), `test`, `build`.
- `BridgeCommandClient` / `LocalBridgeClient` already fail open on a dead socket
  (connect throws → CLI swallows). The bridge-security slice's rule
  `bridge-transport-invariants` documents the fail-open-hooks contract this test
  will pin.

## Load-bearing list
- **`Package.swift`** — adding `swiftSettings` with `-warnings-as-errors` to the
  targets (or the harness flag path). Must not break `swift build`, `swift test`,
  Xcode `open Package.swift`, or `package-app.sh`.
- **`scripts/harness.sh`** — `lint` step (add SwiftLint), possibly `build`/`test`
  (warnings flag). The `ci` aggregate must stay green.
- **`.github/workflows/ci.yml`** — install SwiftLint; keep both jobs green.
- **`CodexSessionTrackingTests.swift:695`** — the one existing warning to fix
  (behavior-neutral: `let initialSnapshot` → `_` or use it).
- **`IslandDebugScenario.swift` + `HarnessLaunchConfiguration.swift`** — the
  `#if DEBUG` boundary; harness scenarios must still resolve in debug builds and
  the `swift test`/smoke harness must still compile.
- **`OpenIslandHooks` CLI fail-open path** (`OpenIslandHooksCLI.swift`,
  `BridgeCommandClient`) — the invariant the new test pins; must not change.
- **New `.swiftlint.yml`** — rule set + thresholds calibrated so the current tree
  passes.

## Out of scope
- Any code change driven by *new* lint rules beyond making the current tree pass
  (no mass reformat, no fixing pre-existing style the curated rules don't flag).
- Enabling additional experimental/upcoming Swift feature flags or bumping the
  language mode.
- The `@unchecked Sendable` audit (discovery #8 code-smell) — removing/justifying
  the 26 usages is a separate effort; the warnings gate doesn't force it.
- Installer/bridge/reducer behavior (prior + future slices).
- Adding dedicated test targets for `OpenIslandHooks`/`OpenIslandSetup`
  (discovery #2 build-config) beyond the single fail-open test — a broader
  coverage push is its own slice.

## Acceptance
- **A1 — no warnings.** A clean `swift build --build-tests` produces **zero**
  Swift warnings; the `CodexSessionTrackingTests.swift:695` warning is gone.
- **A2 — warnings gate active.** A deliberately-introduced warning (e.g. an unused
  `let` added temporarily) causes `scripts/harness.sh ci` to **fail**; removing it
  restores green. (Demonstrate/describe the mechanism; the gate is wired via
  `Package.swift` swiftSettings or the harness build/test flag.)
- **A3 — SwiftLint wired and green.** `.swiftlint.yml` exists; `scripts/harness.sh
  lint` runs SwiftLint (when installed) and the **current tree passes** with no
  violations at the configured level; CI installs and runs it. Absence of the
  binary locally degrades gracefully (documented), but CI runs it for real.
- **A4 — no shipped PII.** A release-config build
  (`swift build -c release`) contains no `/Users/wangruobing` (or any personal
  home path) — assert via `strings`/grep over the release binary, or by the
  `#if DEBUG` guard making the literals debug-only. Debug harness scenarios still
  function.
- **A5 — fail-open covered.** A test drives the hook CLI / its send path against a
  non-existent bridge socket and asserts it neither blocks nor emits a deny/error
  directive (agent proceeds). It runs in the normal `swift test` suite.
- **A6 — gate green.** `zsh scripts/harness.sh ci` and `package-app.sh` both pass;
  no new warnings; the current tree passes SwiftLint.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
