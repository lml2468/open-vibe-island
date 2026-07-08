---
type: Journal
title: "Journal: ui-decomposition"
description: Split the 2,779-LOC IslandPanelView by relocating self-contained sub-views/styles/theme into sibling files — verbatim, no behavior change
tags: ["refactor", "ui", "swiftui", "maintainability", "decomposition"]
timestamp: 2026-07-08T09:18:23Z
slug: ui-decomposition
source: self
---

# Journal: ui-decomposition

Seventh and final implemented slice of the `arch-quality-audit` discovery
(finding #5). Pure code relocation — no behavior change.

## What was done

`IslandPanelView.swift` went from **2,779 → 1,128 LOC** (−1,651) by moving eight
self-contained top-level types into sibling files under `Views/`:

- `IslandSessionRow.swift` (~872) — the biggest win
- `StructuredQuestionPromptView.swift` (~408)
- `ReplyTextField.swift` (+ its NSViewRepresentable, ~93)
- `IslandButtonStyles.swift` (both button styles)
- `IslandMarkdownTheme.swift` (the MarkdownUI theme extension)
- `DismissButton.swift`
- `IslandPanelSupport.swift` (shared `AutoHeightScrollView`, `ContentHeightKey`,
  `ConditionalDrawingGroup`, `IslandSessionRowPresentation`)
- `IslandPanelStringSupport.swift` (the `trimmedForNotificationCard` String ext)

Each move is verbatim — the only edits are `private`→`internal` where a type is
now referenced across files, plus per-file imports. The diff to
`IslandPanelView.swift` is **1,651 deletions, 0 additions**, so no remaining code
(and no literal / design token / view body) was touched. `NotificationContentHeightKey`
correctly stayed `private` in the main file (used only there).

## Verification

- Verbatim proof: each moved type diffed byte-for-byte against `origin/main`
  (modulo the visibility keyword) — identical.
- `swift build` + full `swift test` (382 tests) pass under warnings-as-errors +
  `swiftlint --strict`, 0 violations.
- Render check: the app builds and launches with the `sessionList` debug scenario
  and auto-exits cleanly.

## Learning

- **For an untestable-by-unit-tests SwiftUI file, decompose by verbatim
  relocation, and prove it with a deletions-only diff.** A move is safe to claim
  behavior-neutral only if (a) the source file's diff is pure deletions and (b)
  each moved block diffs identically against the base. Anything else (reflowing,
  token substitution, body splitting) is a behavior-*risking* change that belongs
  in a separate, separately-verified slice.
- **Watch shared file-private types when splitting a file.** The one real hazard
  in a mechanical move was `IslandSessionRowPresentation`, used by BOTH the
  extracted row and the main view — it had to land `internal` in a shared support
  file, not move with the row. warnings-as-errors caught the `private`-across-files
  mistake at build time. Captured in the `view-file-decomposition` rule.
- This completes all seven slices of `arch-quality-audit`. See `.octospec/log.md`.
