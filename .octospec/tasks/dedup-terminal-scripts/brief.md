---
type: Task
title: "Task: dedup-terminal-scripts"
description: Extract the byte-identical Ghostty/Terminal AppleScript source-string literals into shared constants in TerminalProbeSupport
tags: ["dedup", "applescript", "terminal", "maintainability"]
timestamp: 2026-07-09T05:25:24Z
# --- octospec extension fields ---
slug: dedup-terminal-scripts
upstream: arch-quality-audit-r2 (discovery finding #9, cluster A)
source: self
revision: 1
approvals: []
---

# Task: dedup-terminal-scripts

> Eleventh slice of the `arch-quality-audit-r2` discovery — the third cut of
> finding #9 **cluster A**, into the `TerminalProbeSupport` shared home.
> Independent branch off `origin/main`.

## Goal

The Ghostty and Terminal.app AppleScript **source-string literals** are
byte-identical between `TerminalJumpTargetResolver.swift` (Ghostty `:671-697`,
Terminal `~:716-745`) and `TerminalSessionAttachmentProbe.swift` (Ghostty
`:1174-1200`, Terminal `~:1218-1244`) — verified byte-for-byte, with **no Swift
interpolation** (the `fieldSeparator`/`recordSeparator` inside are AppleScript-level
vars set to `ASCII character 31/30`). Extract the two literals into shared
`static let` constants on `TerminalProbeSupport` and reference them from both
files' `let script = ...` sites.

The surrounding **parse wrappers stay per-file** (the Resolver uses
`try? runAppleScript(...)` returning an optional; the Probe uses
`try runAppleScript(...)` that throws) — only the string literals move. Behavior
is unchanged (identical strings); this is a pure de-duplication of ~50 lines of
AppleScript into one place.

## Background

- The scripts are inline `let script = """…"""` locals inside private methods with
  **no named symbol and no external references** — so no typealias/shim is needed
  (unlike the snapshot-struct slice). Each of the four `let script = """…"""`
  bodies is simply replaced with a reference to the shared constant.
- The per-file Swift separator constants used to *parse* the output
  (`fieldSeparator = "\u{1F}"` vs `"\u{1f}"` — same code point, cosmetic diff) are
  **out of scope**: they belong to the parse wrappers, not the script literals.
  Leave them as-is (a later slice may unify them if worth it).
- Like `dedup-terminal-snapshots`, this is a **pure verbatim relocation** — its
  acceptance is `N/A(test)` (a string constant has no non-circular failing-first
  unit test), proven by a byte-identical constant + the existing suites passing.
  This framing is set in r1 up front (learned from that slice's r2 iterate).
- **Injected rule:** `terminal-jump-resilience` matches both files (touches: jump)
  — behavior must be preserved.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **The 4 inline AppleScript literals** (Ghostty + Terminal in each of
  `TerminalJumpTargetResolver` and `TerminalSessionAttachmentProbe`) — replaced by
  references to 2 shared constants. `[applescript] [terminal]`
- **New `TerminalProbeSupport.ghosttyEnumerationScript` /
  `terminalEnumerationScript`** (`static let`) — the shared home; their exact text
  defines correctness (must equal the pre-move literals byte-for-byte). `[terminal]`
- **The per-file parse wrappers** (`ghosttySnapshots`/`terminalSnapshots` in the
  Probe; the resolver equivalents) — their logic (optional vs throwing, the
  separator parsing) is UNCHANGED; only the `script` value they use moves.
  `[applescript]`

## Out of scope
- **The parse wrappers** themselves, `runAppleScript`, `isRunning`,
  `corrected*JumpTarget`, and the iTerm script (Probe-only — no duplicate to
  dedup). Later slices / not applicable.
- **The `fieldSeparator`/`recordSeparator` Swift parse constants** (`\u{1F}` vs
  `\u{1f}`) — cosmetic, belong to the wrappers; not touched.
- No behavior change, no AppleScript text change, no public API change beyond
  adding the two shared constants.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — the two AppleScript literals are shared `static let` constants.**
  `TerminalProbeSupport.ghosttyEnumerationScript` and
  `TerminalProbeSupport.terminalEnumerationScript` exist and contain the exact
  AppleScript source (the `set fieldSeparator to ASCII character 31 … end tell`
  program). *(N/A(test): a verbatim string relocation — the only "test" is
  constant-equals-itself (circular). Proven by the moved constants being
  byte-identical to the four deleted literals and by A3/A4.)*
- **A2 — both files reference the shared constants (no inline duplicate remains).**
  All four `let script = """…"""` sites now use
  `TerminalProbeSupport.ghosttyEnumerationScript` /
  `.terminalEnumerationScript`; the AppleScript program text exists in exactly one
  place per script. *(Verifiable by grep: the `tell application "Ghostty"` /
  `tell application "Terminal"` literal appears once each in `Sources/`.)*
- **A3 — the shared constants are byte-identical to the removed literals.** The
  moved text matches the pre-move literals character-for-character (diff against
  `origin/main`). *(Verifiable: git diff shows the four literals deleted and the
  two constants added with identical body text.)*
- **A4 — behavior neutral + gate green (the real proof).** The existing
  `TerminalSessionAttachmentProbeTests` (~40 cases, which exercise the snapshot
  parsing) and `AppModelSessionListTests` pass **unchanged**; `swift build` +
  `swift test` pass under the repo gate (warnings-as-errors + `swiftlint
  --strict`). *(N/A(test): the gate + pre-existing suites ARE the behavior-neutral
  proof for a pure literal move.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
