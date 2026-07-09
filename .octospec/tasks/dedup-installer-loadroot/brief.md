---
type: Task
title: "Task: dedup-installer-loadroot"
description: Extract the 4 near-identical loadRootObject(from:) copies in the JSON hook installers into a shared JSONConfigSerialization helper, parameterizing the per-file error
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T07:43:19Z
# --- octospec extension fields ---
slug: dedup-installer-loadroot
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — second cut)
source: self
revision: 1
approvals: []
---

# Task: dedup-installer-loadroot

> Seventeenth slice of the `arch-quality-audit-r2` discovery — the second cut of
> finding #9 **cluster B**, extending the `JSONConfigSerialization` helper started
> by the serialize slice. Independent branch off `origin/main`.

## Goal

The 4 JSON-config installers (Claude/Codex/Cursor/Gemini) each carry a
`loadRootObject(from:)` that is identical **except the thrown error type** (and
cosmetic brace style):
```swift
private static func loadRootObject(from data: Data?) throws -> [String: Any] {
    guard let data else { return [:] }
    let object = try JSONSerialization.jsonObject(with: data)
    guard let rootObject = object as? [String: Any] else {
        throw <PerFileError>   // invalidSettingsJSON / invalidHooksJSON
    }
    return rootObject
}
```
Extract a shared `JSONConfigSerialization.loadRootObject(from:invalidError:)` that
takes the per-file error via `@autoclosure`, and reduce each installer's copy to a
one-line delegate passing its own error (Claude
`ClaudeHookInstallerError.invalidSettingsJSON`, Codex
`CodexHookInstallerError.invalidHooksJSON`, Cursor
`CursorHookInstallerError.invalidHooksJSON`, Gemini
`GeminiHookInstallerError.invalidSettingsJSON`). Kimi (TOML) has no
`loadRootObject` — untouched.

Behavior is unchanged: `nil data → [:]`, valid dict → returned, and — critically —
**non-dictionary JSON throws** (never resets to `[:]`), each installer keeping its
own error. This preserves `installer-config-safety`.

## Background

- All 4 installers are `public enum …HookInstaller` in OpenIslandCore; the 8 call
  sites (`try loadRootObject(from: existingData)` in each install + uninstall path)
  are in `static` context.
- **Config-safety load-bearing behaviors that MUST be preserved** (from the
  `installer-config-safety` rule): (1) absent file / nil data → start-fresh `[:]`,
  NOT an error; (2) present-but-non-dictionary → **throw**, never fall back to `[:]`
  and overwrite (that's the reset-on-parse-failure the rule forbids). The shared
  helper keeps both, with the throw carrying each caller's own error type.
- Extends the `JSONConfigSerialization` file from the prior (merged) serialize
  slice; mirrors the same test-backed dedup shape.
- **Injected rule:** `installer-config-safety` (load-bearing) matches
  `*HookInstaller.swift`.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 4 `loadRootObject` definitions** (`ClaudeHookInstaller.swift:151`,
  `CodexHookInstaller.swift:283`, `CursorHookInstaller.swift:129`,
  `GeminiHookInstaller.swift:114`) — become one-line delegates to the shared
  helper, each passing its own error. `[installer] [config]`
- **The 8 call sites** (Claude `:74,:117`; Codex `:98,:133`; Cursor `:56,:90`;
  Gemini `:55,:82`) — must behave identically (nil→[:], dict→dict, non-dict→throw
  the SAME per-file error). `[installer] [config]`
- **New `JSONConfigSerialization.loadRootObject(from:invalidError:)`** — the shared
  home; its three-way behavior (nil / dict / throw) defines correctness. `[config]`

## Out of scope
- **The rest of cluster B** — the divergent command-detection predicates, the
  `sanitize`/hook-array mutators (risky config-write surface), and the manager
  base-class extraction. Deferred.
- **Kimi** (TOML, no `loadRootObject`).
- No change to what each installer throws (each keeps its own error type), to the
  nil/dict/non-dict semantics, or to parse/reset/backup logic elsewhere.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — nil data returns empty dictionary (start-fresh, not error).**
  `JSONConfigSerialization.loadRootObject(from: nil, invalidError: SentinelError())`
  returns `[:]` (does not throw). *(Testable: direct call. Fails first — the helper
  does not exist.)*
- **A2 — valid JSON object is returned.** For `{"a":1,"hooks":["x"]}` bytes it
  returns a dictionary with those entries. *(Testable: direct call. Fails first.)*
- **A3 — non-dictionary JSON throws the given error (no reset).** For a top-level
  JSON array (e.g. `[1,2]`) it **throws** the injected `invalidError` (a sentinel),
  NOT `[:]` — proving reset-on-parse-failure does not happen and the per-file error
  is propagated. Also, malformed JSON throws (JSONSerialization's own error).
  *(Testable: direct call asserting throw + the sentinel identity. Fails first.)*
- **A4 — no duplicated `loadRootObject` body remains; installers delegate with
  their own errors.** Each installer's `loadRootObject` is a one-line delegate; the
  parse/guard body exists in exactly one place; each still surfaces its own error
  type on non-dict input. *(Verifiable by grep + a per-installer throw test if
  cheap.)*
- **A5 — behavior neutral + gate green.** Existing installer suites
  (`ClaudeHooksTests`/`CursorHooksTests`/`GeminiHooksTests` + Codex) pass unchanged;
  `swift build` + `swift test` pass under the repo gate (warnings-as-errors +
  `swiftlint --strict`). *(N/A(test): the gate + existing suites are the
  behavior-neutral proof.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
