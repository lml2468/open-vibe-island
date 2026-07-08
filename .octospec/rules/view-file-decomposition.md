---
type: Rule
title: View-file decomposition
description: How to safely split a large SwiftUI view file — verbatim relocation, visibility discipline, deletions-only diff as the equivalence proof.
tags: ["ui", "swiftui", "refactor", "decomposition"]
timestamp: 2026-07-08T09:18:23Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: view-file-decomposition
tier: repo
priority: 70
load_bearing: false
inject_when:
  paths:
    - "Sources/OpenIslandApp/Views/**"
  touches: ["ui", "swiftui", "decomposition"]
source: self
supersedes: []
---

# View-file decomposition

These SwiftUI views have no unit-test harness and the smoke harness is flaky
headless, so behavior equivalence can't be asserted by tests. When splitting a
large view file, make the change **provably** behavior-neutral.

## Verbatim relocation only

- Move a type by cutting it **verbatim** into a new sibling file. The only
  permitted edits are: the visibility keyword (`private`→`internal` when the type
  is now referenced across files) and per-file `import`s. No reflowing, no
  renames, no literal/token/body edits.
- The equivalence proof is the diff: the source file's change must be
  **deletions-only** (no `+` lines to remaining code), and each moved block must
  diff identically against the base branch (modulo the visibility keyword).
- Behavior-*changing* work — reviving design tokens (raw literals →
  `IslandOpacity`/etc.), extracting view models, splitting a giant `body`,
  de-duplicating view trees — is out of scope for a relocation and belongs in its
  own separately-verified slice.

## Visibility discipline

- Before moving a `private` type, grep every usage. A type used by BOTH the moved
  code and the code left behind must become `internal` in a **shared** file, not
  move with one side. A type used only where it lands stays `private`.
- warnings-as-errors + `swiftlint --strict` (see [[ci-quality-gates]]) will catch
  a `private`-across-files mistake at build time — run the gate, don't eyeball it.

## Proof of life

- After the move, build and launch the app with a debug scenario
  (`OPEN_ISLAND_HARNESS_SCENARIO=<name> … swift run OpenIslandApp`) as a
  best-effort render check. If headless flakiness blocks it, say so and rely on
  the deletions-only diff + full gate.
