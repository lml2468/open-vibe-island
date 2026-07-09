---
type: Task
title: "Task: dedup-shellquote"
description: Extract the 5 byte-identical shellQuote copies in the hook installers into one shared ShellQuoting helper, with a unit test
tags: ["dedup", "installer", "shell", "security", "maintainability"]
timestamp: 2026-07-08T13:50:03Z
# --- octospec extension fields ---
slug: dedup-shellquote
upstream: arch-quality-audit-r2 (discovery finding #9, cluster C)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T01:36:33Z
---

# Task: dedup-shellquote

> Sixth slice of the `arch-quality-audit-r2` discovery — the first, smallest
> piece of finding #9 (systemic duplication). A clean, low-risk extraction of one
> pure helper. Independent branch off `origin/main`.

## Goal

Replace the **five byte-identical `shellQuote` copies** across the hook installers
with one shared, unit-tested helper. Current copies (all `private static func
shellQuote(_:) -> String`, logic identical modulo brace whitespace):
- `ClaudeHookInstaller.swift:312`, `CodexHookInstaller.swift:578`,
  `CursorHookInstaller.swift:160`, `GeminiHookInstaller.swift:167`,
  `KimiHookInstaller.swift:237`.

The logic (POSIX single-quote shell escaping) is:
```swift
guard !string.isEmpty else { return "''" }
return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
```
Introduce `ShellQuoting.quote(_:)` in a new small OpenIslandCore file, delete the
five private copies, and route every call site through it. Behavior is unchanged
(the copies are already identical) — this is pure de-duplication that also shrinks
the future installer-base refactor (cluster B).

## Background

- All five installers are `public enum …HookInstaller` in the **OpenIslandCore**
  target, and all five call sites are in `static` context (the hook-command string
  builders: Gemini:48, Cursor:49, Kimi:52, Codex:91, Claude:67), so a shared
  `static` helper in Core is trivially reachable — no cross-target/visibility
  concerns, mechanical substitution.
- OpenIslandCore has no existing string/shell util file, so a new tiny
  `Sources/OpenIslandCore/ShellQuoting.swift` (an `enum ShellQuoting` with a
  `static func quote`) is the cleanest home.
- `shellQuote` is currently **untested**. It is security-relevant (it escapes a
  binary path into a shell command written to third-party config), so a dedicated
  unit test is worth adding as part of the extraction.
- **Injected rule:** `installer-config-safety` (load-bearing) matches
  `*HookInstaller.swift`. This change doesn't alter config-writing behavior, but
  the escaping it governs is exactly the safety concern — the shared helper must
  preserve the exact escaping semantics.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 5 `shellQuote` definitions** (`Claude:312`, `Codex:578`, `Cursor:160`,
  `Gemini:167`, `Kimi:237`) — deleted and replaced by the shared helper.
  `[installer] [shell]`
- **The 5 call sites** (`Gemini:48`, `Cursor:49`, `Kimi:52`, `Codex:91`,
  `Claude:67`) — the exact command strings each installer writes into agent config;
  their output must be **byte-identical** before/after. `[installer] [config]`
- **New `ShellQuoting.quote`** — the shared home; its output defines correctness.
  `[shell]`

## Out of scope
- **The full installer base/protocol refactor** (finding #9 cluster B —
  loadRootObject/serialize/sanitize/status-install-uninstall skeletons). This slice
  extracts only `shellQuote`.
- **The AppleScript probe cluster** (cluster A) and **`escapeAppleScript`** (a
  different helper in the App target) — separate slices.
- No change to what command string any installer writes, to config-file behavior,
  or to any public API beyond adding `ShellQuoting`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `ShellQuoting.quote` implements POSIX single-quote escaping.** It returns
  `''` for empty input; wraps a plain string in single quotes
  (`abc` → `'abc'`); wraps a path with spaces (`/a b/c` → `'/a b/c'`); and escapes
  embedded single quotes via the `'\''` idiom
  (`a'b` → `'a'\''b'`). *(Testable: direct unit test of the pure function. Fails
  first — the helper does not exist.)*
- **A2 — every installer's command string is unchanged (dedup is behavior-neutral).**
  The five installers still produce their exact current hook-command strings for a
  representative binary path (including one with a space/quote). *(Testable:
  assert each installer's built command equals the expected string; equivalently,
  the shared helper's output equals the pre-extraction copies'. Preservation
  guard.)*
- **A3 — no `private static func shellQuote` remains in any installer.** The five
  copies are gone; all route through `ShellQuoting`. *(Verifiable by grep / the
  fact that the build compiles with the copies removed.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
