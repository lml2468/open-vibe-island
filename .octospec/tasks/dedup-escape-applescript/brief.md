---
type: Task
title: "Task: dedup-escape-applescript"
description: Extract the 2 identical escapeAppleScript copies into one shared AppleScriptEscaping helper, with a unit test
tags: ["dedup", "applescript", "jump", "maintainability", "security"]
timestamp: 2026-07-09T02:43:59Z
# --- octospec extension fields ---
slug: dedup-escape-applescript
upstream: arch-quality-audit-r2 (discovery finding #9, cluster C)
source: self
revision: 1
approvals: []
---

# Task: dedup-escape-applescript

> Eighth slice of the `arch-quality-audit-r2` discovery — the second small piece
> of finding #9 cluster C (after `dedup-shellquote`). A clean, low-risk extraction
> of one pure helper. Independent branch off `origin/main`.

## Goal

Replace the **two identical `escapeAppleScript` copies** with one shared,
unit-tested helper. Current copies (logic identical modulo brace whitespace and
instance-vs-static shape):
- `TerminalJumpService.swift:1388` — `private func escapeAppleScript(_:) -> String`
  (instance method), 7 call sites (the iTerm/Ghostty/Terminal AppleScript builders).
- `TerminalTextSender.swift:155` — `private static func escapeAppleScript(_:) -> String`,
  4 call sites.

The logic escapes a value for embedding inside an AppleScript double-quoted
string:
```swift
guard let value else { return "" }
return value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
```
Introduce `AppleScriptEscaping.escape(_:)` (a static helper on a new tiny type),
delete the two private copies, and route every call site through it. Behavior is
unchanged (the copies are already identical) — pure de-duplication.

## Background

- Both files are in the **OpenIslandApp** target, so a shared helper there is
  reachable from both; the JumpService copy is an instance method and the
  TextSender copy is static, so the extraction normalizes both call shapes to a
  single `static func` (the JumpService call sites change from `escapeAppleScript(x)`
  to `AppleScriptEscaping.escape(x)`).
- This mirrors the just-merged `dedup-shellquote` slice (shared `ShellQuoting.quote`
  + unit test). Cleanest home: a new tiny
  `Sources/OpenIslandApp/AppleScriptEscaping.swift`.
- **Do NOT conflate with `TerminalJumpService.escapeJSONStringContents`** — a
  *different* escaper (full JSON control-char escaping) already unit-tested in
  `Tests/OpenIslandAppTests/TerminalJumpServiceEscapeTests.swift`. Leave it alone.
  The AppleScript escaper is currently **untested**; this adds coverage.
- **Injected rule:** `terminal-jump-resilience` matches `TerminalJumpService.swift`
  (touches: jump). This change is behavior-neutral to the jump path — the escaping
  it governs must be preserved exactly.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 2 `escapeAppleScript` definitions** (`TerminalJumpService.swift:1388`,
  `TerminalTextSender.swift:155`) — deleted and replaced by the shared helper.
  `[applescript] [jump]`
- **The 11 call sites** (7 in `TerminalJumpService` building iTerm/Ghostty/Terminal
  scripts; 4 in `TerminalTextSender`) — the AppleScript fragments they build must be
  **byte-identical** before/after. `[jump] [applescript]`
- **New `AppleScriptEscaping.escape`** — the shared home; its output defines
  correctness. `[applescript]`

## Out of scope
- **The AppleScript probe cluster** (finding #9 cluster A — the duplicated
  Ghostty/Terminal script *sources* + runners + snapshot structs between
  `TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe`). This slice
  extracts only the `escapeAppleScript` string helper, not the script bodies.
- **`escapeJSONStringContents`** (a different, already-tested escaper) — untouched.
- **The installer base refactor** (cluster B) and per-agent metadata mergers /
  mirrored events (#10) — separate slices.
- No change to any AppleScript the jump/send path builds, or to any public API
  beyond adding `AppleScriptEscaping`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `AppleScriptEscaping.escape` escapes AppleScript double-quote-string
  content.** It returns `""` for nil; passes a plain string through unchanged
  (`abc` → `abc`); escapes a backslash (`a\b` → `a\\b`); escapes a double quote
  (`a"b` → `a\"b`); and escapes a backslash-before-quote in the correct order
  (`\"` → `\\\"`). *(Testable: direct unit test of the pure function. Fails first —
  the helper does not exist.)*
- **A2 — the jump/send AppleScript fragments are unchanged (dedup is
  behavior-neutral).** `TerminalJumpService` and `TerminalTextSender` still build
  their exact current escaped strings for representative inputs (including one with
  a quote/backslash). *(Testable: assert the shared helper's output equals the
  pre-extraction copies' for those inputs; equivalently, existing jump/send tests
  still pass. Preservation guard.)*
- **A3 — no `func escapeAppleScript` remains in either file.** Both copies are
  gone; all 11 call sites route through `AppleScriptEscaping`. *(Verifiable by grep
  / the build compiling with the copies removed.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
