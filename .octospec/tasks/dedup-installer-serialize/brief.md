---
type: Task
title: "Task: dedup-installer-serialize"
description: Extract the 4 byte-identical serialize(_:) copies in the JSON hook installers into one shared JSONConfigSerialization helper, with a unit test
tags: ["dedup", "installer", "config", "maintainability"]
timestamp: 2026-07-09T07:18:51Z
# --- octospec extension fields ---
slug: dedup-installer-serialize
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — first cut)
source: self
revision: 1
approvals: []
---

# Task: dedup-installer-serialize

> Sixteenth slice of the `arch-quality-audit-r2` discovery — the first, smallest,
> lowest-risk cut of finding #9 **cluster B** (hook-installer boilerplate).
> Independent branch off `origin/main`.

## Goal

The 4 JSON-config hook installers (Claude/Codex/Cursor/Gemini) each carry a
**byte-identical** private `serialize(_:)`:
```swift
private static func serialize(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}
```
Extract it into `JSONConfigSerialization.serialize(_:)` in a new
`Sources/OpenIslandCore/JSONConfigSerialization.swift`, delete the 4 private
copies, and route all 8 call sites through it. (Kimi is TOML-based and has no
`serialize` — untouched.)

Behavior is unchanged (the copies are identical; the options — hence the exact
on-disk bytes — are preserved), so `installer-config-safety` is preserved. This is
pure de-duplication and, because the extracted helper is pure, it gets a real
unit test.

## Background

- All 4 installers are `public enum …HookInstaller` in **OpenIslandCore**; all 8
  call sites (`serialize(rootObject)` in each installer's install + uninstall path)
  are in `static` context, so a shared `static` helper is trivially reachable —
  mechanical substitution.
- Mirrors the merged `ShellQuoting` slice (shared pure helper + unit test) and the
  `ConfigBackup` precedent (single-purpose OpenIslandCore file). Cleanest home is a
  new tiny `JSONConfigSerialization.swift`.
- **Injected rule:** `installer-config-safety` (load-bearing) matches
  `*HookInstaller.swift`. This change does NOT alter parse/reset/backup logic (that
  lives in the managers / `ConfigBackup`); it only relocates the serializer. The
  `.sortedKeys` determinism the safety rule relies on (stable output → no spurious
  "changed"→backup) must be preserved exactly — which it is, since the options are
  unchanged.
- `serialize` is currently **untested**; this adds the coverage.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 4 `serialize` definitions** (`ClaudeHookInstaller.swift:164`,
  `CodexHookInstaller.swift:296`, `CursorHookInstaller.swift:140`,
  `GeminiHookInstaller.swift:125`) — deleted; replaced by the shared helper.
  `[installer] [config]`
- **The 8 call sites** (Claude `:94,:142`; Codex `:120,:157`; Cursor `:73,:120`;
  Gemini `:66,:106`) — the exact JSON bytes each installer writes to agent config
  must be **byte-identical** before/after. `[installer] [config]`
- **New `JSONConfigSerialization.serialize`** — the shared home; its output
  (pretty-printed + sorted keys) defines correctness. `[config]`

## Out of scope
- **The rest of cluster B** — `loadRootObject(from:)` (needs error
  parameterization; the good *next* slice), the divergent command-detection
  predicates, the `sanitize`/`containsManagedHook`/hook-array mutators (risky
  config-write surface), and the manager `status/install/uninstall` base-class
  extraction. All deferred.
- **Kimi** (TOML, no `serialize`).
- No change to what config any installer writes, to parse/reset/backup logic, or
  to any public API beyond adding `JSONConfigSerialization`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `JSONConfigSerialization.serialize` produces pretty-printed, key-sorted
  JSON.** For `["b": 1, "a": 2]` it returns UTF-8 bytes whose decoded string has
  `"a"` before `"b"` (sorted) and is pretty-printed (contains newlines /
  indentation), and round-trips back to the same dictionary. *(Testable: direct
  unit test of the pure function. Fails first — the helper does not exist.)*
- **A2 — empty dictionary serializes to the pretty-printed empty form.**
  `serialize([:])` decodes to `"{\n\n}"` (the JSONSerialization pretty-printed
  empty-object form). *(Testable: matters because installers write this back on
  an empty root; asserts the exact bytes. Fails first.)*
- **A3 — no `private static func serialize` remains in any JSON installer.** The 4
  copies are gone; all route through `JSONConfigSerialization`. *(Verifiable by
  grep / the build compiling with the copies removed.)*
- **A4 — behavior neutral + gate green.** The existing installer test suites
  (`ClaudeHooksTests`, `CursorHooksTests`, `GeminiHooksTests`, plus Codex coverage)
  pass unchanged — the written config bytes are identical; `swift build` +
  `swift test` pass under the repo gate (warnings-as-errors + `swiftlint --strict`).
  *(N/A(test): the gate + existing suites are the behavior-neutral proof.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
