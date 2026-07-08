---
type: Task
title: "Task: ui-decomposition"
description: Split the 2,779-LOC IslandPanelView by relocating its self-contained sub-views/styles/theme into sibling files — pure code movement, no behavior change
tags: ["refactor", "ui", "swiftui", "maintainability", "decomposition"]
timestamp: 2026-07-08T08:57:36Z
# --- octospec extension fields ---
slug: ui-decomposition
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-08T08:58:53Z
---

# Task: ui-decomposition

> Seventh (final) slice of the `arch-quality-audit` discovery (finding #5). This
> file is a 2,779-line SwiftUI grab-bag; a behavior-changing refactor of view
> logic can't be proven equivalent without a running UI, so this slice is scoped
> to **pure code relocation** — moving self-contained types into sibling files
> with no logic change. Design-token revival (#17) and view-logic extraction (view
> models, splitting `IslandSessionRow`'s body) are explicitly deferred; see Out of
> scope.

## Goal
`Sources/OpenIslandApp/Views/IslandPanelView.swift` (2,779 LOC) holds ~15
top-level types: the main `IslandPanelView`, plus self-contained sub-views,
button styles, a Markdown theme, preference keys, and small helpers. Relocate the
**self-contained** types into their own files under `Sources/OpenIslandApp/Views/`
so the file shrinks to `IslandPanelView` + its tightly-coupled helpers, and each
moved component is independently findable.

This is **mechanical**: cut a type verbatim into a new file, change `private
struct` → `struct` (or keep `private` where it stays in the same file), add the
needed `import`s. No renaming, no body edits, no logic change. Because it's the
same module, `private`→internal visibility keeps everything reachable; the
compiled behavior is identical (the build + full test/gate is the equivalence
proof).

Extract into sibling files (all used only within this file today, verified):
- `IslandSessionRow` (~872 LOC) → `IslandSessionRow.swift` (the biggest win)
- `StructuredQuestionPromptView` (~412 LOC) → `StructuredQuestionPromptView.swift`
- `ReplyTextField` + `_ReplyTextFieldRepresentable` (~102) → `ReplyTextField.swift`
- `IslandCompactButtonStyle` + `IslandActionButtonStyle` (~96) → `IslandButtonStyles.swift`
- `MarkdownUI.Theme` extension + `DismissButton` (~111) → `IslandMarkdownTheme.swift`
  (or split `DismissButton` into its own file — implementer's call)
- The small shared helpers (`AutoHeightScrollView`, `ContentHeightKey`,
  `NotificationContentHeightKey`, `ConditionalDrawingGroup`) → a
  `IslandPanelSupport.swift` if it reads cleanly; otherwise leave in place.

Leave in `IslandPanelView.swift`: `IslandPanelView` itself and the presentation
structs it owns inline (`UsageProviderPresentation`, `UsageWindowPresentation`,
`OpenedHeaderMetrics`, `SessionOverviewItem`, `AgentSession` extension) unless a
clean move presents itself. The target is a materially smaller main file, not a
specific line count.

## Background
- Verified (grep): `IslandSessionRow`, `StructuredQuestionPromptView`,
  `ReplyTextField`, both button styles, and `DismissButton` are referenced **only**
  within `IslandPanelView.swift`. `AutoHeightScrollView` is only *mentioned* in
  `OverlayPanelController` comments, not used there. So all are safely movable
  within the module by relaxing `private`.
- The repo now enforces warnings-as-errors + `swiftlint --strict` (quality-gates
  slice). Moved code must pass both — watch for SwiftLint file-scoped
  expectations, and for `private`→`internal` exposing a name that trips a rule.
- There is **no** UI test harness for these views; the smoke harness
  (`scripts/harness.sh smoke`) renders scenarios but is documented as flaky
  headless. Equivalence rests on: identical source (verbatim moves), a clean
  build, the full test suite, and — where feasible — a manual/harness render.

## Load-bearing list
- **`IslandPanelView.swift`** — the source file being split; every moved type and
  the remaining `IslandPanelView` must still compile and render identically.
- **Type visibility** — moved types go from `private` (file-scoped) to
  `internal`; confirm no name collision with existing module-internal types.
- **`OverlayPanelController` / `OverlayUICoordinator`** — host the panel; must be
  unaffected (they reference `IslandPanelView`, not its private sub-types).
- **Design tokens / literals** — left exactly as-is (revival is out of scope); do
  not touch spacing/opacity/color values while moving code.
- **Resource/asset references** in moved views — must resolve from the new file
  (same bundle/module, so unchanged).
- **The gate**: `swift build`, `swift test`, `swiftlint --strict`.

## Out of scope
- **#17 design-token revival** — replacing raw literals (`0.055`, `cornerRadius:
  10`, etc.) with `IslandOpacity`/`IslandRadius`/tokens. That changes values'
  provenance and risks visual drift; its own slice.
- **View-logic extraction** — introducing view models, splitting
  `IslandSessionRow`'s 800-line body into smaller subviews, de-duplicating
  `sessionListContent` vs `sessionRowsContent`, moving geometry math out of the
  view. All behavior-affecting; separate slices.
- **Business logic in the view** (e.g. the inline `ClaudePermissionUpdate`
  construction, discovery #2) — not touched here.
- Renaming any type, or changing any view body / modifier / literal.
- Touching `OverlayPanelController` height-estimation duplication (#5 sub-finding).

## Acceptance
- **A1 — file materially smaller.** `IslandPanelView.swift` drops by ≳1,300 LOC
  (the row + question-prompt + reply + styles + theme moves); the extracted types
  live in their own files under `Sources/OpenIslandApp/Views/`.
- **A2 — verbatim moves.** Each moved type's body is unchanged (a diff shows the
  lines removed from `IslandPanelView.swift` and added to the new file are
  identical modulo the `private`→`struct`/`extension` visibility keyword and
  added imports). No renames, no literal/logic edits.
- **A3 — visibility correct.** Moved types are `internal` (or `public` only if
  already so); no `private` type is referenced across files. No name collisions.
- **A4 — behavior neutral.** `swift build` and the full `swift test` suite pass
  unchanged (same test count, no new failures); no view body / modifier / literal
  changed (grep the diff for token/opacity/radius changes → none).
- **A5 — gate green.** `zsh scripts/harness.sh ci` passes (warnings-as-errors +
  `swiftlint --strict`); no new warnings or lint violations.
- **A6 — render check (best effort).** Where the harness can run, capture at least
  one scenario (e.g. `smoke` or `swift run OpenIslandApp` with a debug scenario)
  to confirm the panel still renders; if headless flakiness blocks it, say so in
  the summary and rely on A2/A4.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
