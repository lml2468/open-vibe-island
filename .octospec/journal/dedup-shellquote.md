---
type: Journal
title: "Journal: dedup-shellquote"
description: Extracted the 5 byte-identical shellQuote copies in the hook installers into one shared, unit-tested ShellQuoting helper
tags: ["dedup", "installer", "shell", "security", "maintainability"]
timestamp: 2026-07-09T01:55:00Z
slug: dedup-shellquote
source: self
---

# Journal: dedup-shellquote

Sixth implemented slice of the `arch-quality-audit-r2` discovery — the first,
smallest piece of finding #9 (systemic duplication). A behavior-neutral extraction.

## What was done

Five `*HookInstaller` types (Claude/Codex/Cursor/Gemini/Kimi, all in
OpenIslandCore) each carried a `private static func shellQuote` with byte-identical
POSIX single-quote escaping (only brace-style whitespace differed). Extracted into
one `ShellQuoting.quote(_:)` in a new `Sources/OpenIslandCore/ShellQuoting.swift`,
deleted the five copies, and routed all five call sites through it. The escaping —
previously **untested** despite being shell-injection-relevant — now has a
dedicated `ShellQuotingTests`.

## Verification

- New `ShellQuotingTests` (5): empty→`''`, plain, path-with-spaces, single
  embedded quote→`'\''` idiom, multiple quotes.
- TDD trail: `red:` committed the stub (`quote` returns input unchanged) + the
  call-site swaps + copy deletions, so the tests compiled and failed on assertion;
  Green swapped the 2-line body to the real escaping (`git diff red..green --
  Tests/` = 0 bytes).
- Behavior-neutral proof: the existing installer suites (`ClaudeHooksTests`,
  `CursorHooksTests`, `GeminiHooksTests`, `KimiHooksTests`) exercise the built
  hook-command strings and pass unchanged — the produced commands are
  byte-identical.
- Independent Verify (fresh context) PASS, no findings — confirmed char-for-char
  equivalence and that no `shellQuote` copy remains. Gate green: `harness.sh ci`
  (419 tests) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Prove a "byte-identical copies" dedup with the callers' existing tests, not
  just the new helper's.** The new `ShellQuotingTests` proves the helper is
  *correct*; the pre-existing installer command-string tests prove the extraction
  is *behavior-neutral* (the callers still emit the same strings). Both matter —
  the helper test alone wouldn't catch a call-site that interpolated it in the
  wrong position.
- **A small cluster-C dedup is a safe first step into a big refactor.**
  `shellQuote` physically lived inside the cluster-B installer files, but
  extracting it is independent of and far smaller than the full installer-base
  refactor — it lands a shared helper + test and shrinks cluster B slightly,
  without the risk of restructuring `status/install/uninstall`. The larger
  clusters (A: AppleScript probe; B: installer base) remain their own future
  slices.
