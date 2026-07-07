---
version: alpha
name: Open Island
description: >-
  Visual identity for Open Island, a native macOS notch/"dynamic island" surface
  that tracks AI coding-agent sessions. Ink-on-paper palette with per-status
  accent tints. Values here mirror the Swift token enums in
  Sources/OpenIslandApp/Design/ and are the single source of truth for the look.
colors:
  # Core ink-on-paper (V6ClosedPillShape.swift · V6Palette)
  ink: "#0d0d0f"
  paper: "#f1ead9"
  # Primary accent = the dominant "active" status tint (running). Open Island has
  # no web-style brand primary; running blue is the app's key accent.
  primary: "{colors.running}"
  # Semantic status tints (IslandDesignPalette.Status)
  running: "#6ea7ff"
  completed: "#6fb982"
  waitingForApproval: "#f4a4a4"
  waitingForAnswer: "#ffd58a"
  waitingAggregate: "#e7a762"
  # Agent brand defaults, used when an agent's own brandColorHex is absent
  # (BrandPalette.swift)
  brandCodex: "#8cb8ff"
  brandClaudeCode: "#e68c57"
  brandCursor: "#9ea8ff"
  brandGemini: "#73c7ff"
typography:
  # System font throughout; monospaced for numerics, counts, and pill labels.
  caption:
    fontFamily: system
    fontSize: 10.5px
    fontWeight: 500
    fontFeature: monospaced
  captionEmphasis:
    fontFamily: system
    fontSize: 10.5px
    fontWeight: 600
    fontFeature: monospaced
  body:
    fontFamily: system
    fontSize: 12px
    fontWeight: 500
  bodyEmphasis:
    fontFamily: system
    fontSize: 12px
    fontWeight: 600
  headline:
    fontFamily: system
    fontSize: 13px
    fontWeight: 600
  headlineLarge:
    fontFamily: system
    fontSize: 14px
    fontWeight: 600
  pillLabel:
    fontFamily: system
    fontSize: 11.5px
    fontWeight: 500
    fontFeature: monospaced
  pillCount:
    fontFamily: system
    fontSize: 11px
    fontWeight: 600
    fontFeature: monospaced
rounded:
  # IslandRadius
  xs: 6px
  sm: 8px
  md: 10px
  lg: 12px
  xl: 16px
  pill: 999px
spacing:
  # IslandSpacing
  xxs: 2px
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  xxl: 20px
  xxxl: 24px
components:
  closedPill:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.pillLabel}"
    rounded: "{rounded.pill}"
    padding: "{spacing.md}"
  countBadge:
    textColor: "{colors.paper}"
    typography: "{typography.pillCount}"
    rounded: "{rounded.pill}"
  statusIndicator:
    backgroundColor: "{colors.running}"
    rounded: "{rounded.pill}"
    size: 6px
  # Per-state variants of the indicator dot — its fill is the session's status
  # tint (IslandDesignPalette.Status.tint(for:)). One entry per SessionPhase.
  statusIndicatorRunning:
    backgroundColor: "{colors.running}"
    rounded: "{rounded.pill}"
    size: 6px
  statusIndicatorCompleted:
    backgroundColor: "{colors.completed}"
    rounded: "{rounded.pill}"
    size: 6px
  statusIndicatorWaitingForApproval:
    backgroundColor: "{colors.waitingForApproval}"
    rounded: "{rounded.pill}"
    size: 6px
  statusIndicatorWaitingForAnswer:
    backgroundColor: "{colors.waitingForAnswer}"
    rounded: "{rounded.pill}"
    size: 6px
  # Collapsed-pill roll-up tint when several sessions are summarized.
  statusIndicatorWaitingAggregate:
    backgroundColor: "{colors.waitingAggregate}"
    rounded: "{rounded.pill}"
    size: 6px
  sessionRow:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"
  settingsCard:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: "{spacing.xl}"
  # Appearance-preview tiles — the fallback swatch shown for an agent when it
  # supplies no brandColorHex (BrandPalette). One entry per known agent.
  agentTileCodex:
    backgroundColor: "{colors.brandCodex}"
    rounded: "{rounded.sm}"
    size: 16px
  agentTileClaudeCode:
    backgroundColor: "{colors.brandClaudeCode}"
    rounded: "{rounded.sm}"
    size: 16px
  agentTileCursor:
    backgroundColor: "{colors.brandCursor}"
    rounded: "{rounded.sm}"
    size: 16px
  agentTileGemini:
    backgroundColor: "{colors.brandGemini}"
    rounded: "{rounded.sm}"
    size: 16px
---

# Open Island — DESIGN.md

> This file follows the [`design.md`](https://github.com/google-labs-code/design.md)
> convention: the YAML front matter above holds the **normative token values**;
> the prose below explains **why** they exist and how to apply them. Tokens give
> an agent exact values; this text tells it how they compose.
>
> **Medium note.** Open Island is a native **macOS SwiftUI** app, not a web UI.
> The hex/px values here mirror the Swift token enums in
> `Sources/OpenIslandApp/Design/DesignTokens.swift`,
> `Sources/OpenIslandApp/IslandDesignPalette.swift`, and `…/V6ClosedPillShape.swift`
> (`V6Palette`). When you change a token, change it in **both** places — the Swift
> enum is what ships; this file is what agents read. The Tailwind/CSS export
> targets of the `design.md` CLI are informational only for this project.

## Overview

Open Island lives in the Mac notch. Its whole job is to read at a glance from a
few millimetres of screen, so the identity is deliberately **narrow and
high-contrast**: a near-black *ink* surface, a warm off-white *paper* ink for
glyphs and text, and a small set of **semantic accent tints** that encode a
coding agent's session state (running / completed / waiting). There is no
decorative color — every non-paper hue *means* a status.

The vocabulary is small on purpose. Spacing, radius, opacity, motion, and type
each move along a single coherent ladder (`IslandSpacing`, `IslandRadius`,
`IslandOpacity`, `IslandMotion`, `IslandTypography`). Reach for the nearest step
before inventing a value; do not slot a new value between two steps unless it
carries a distinct semantic meaning.

## Colors

**Core (ink on paper).** `ink` (`#0d0d0f`) is the surface — the pill, panels,
rows, cards. `paper` (`#f1ead9`) is the only "foreground" color: text, glyphs,
the bar glyph tint. This pairing is the brand. Paper-on-ink is the default; ink
does not appear as text.

**Status tints** are the semantic layer. Each maps to exactly one session state
and is the *only* place saturated color appears:

- `running` `#6ea7ff` — an agent is actively working.
- `completed` `#6fb982` — finished / idle-active.
- `waitingForApproval` `#f4a4a4` — blocked on a human approval.
- `waitingForAnswer` `#ffd58a` — blocked on a human answer.
- `waitingAggregate` `#e7a762` — the rolled-up "something is waiting" tint used
  on the collapsed pill when multiple sessions are summarized.

Inactive/idle states are **not** their own hue — they are `paper` at low opacity
(`IslandOpacity.dim`–`muted`), so a dormant session reads as "quiet paper", never
as a color.

**Agent brand defaults** (`brandCodex`, `brandClaudeCode`, `brandCursor`,
`brandGemini`) are *fallbacks* for the appearance preview only, used when an
agent does not supply its own `brandColorHex`. Prefer the agent's declared color;
these exist so the preview never renders colorless.

## Typography

One family — the **system** font — everywhere; weight and a monospaced feature
carry the hierarchy, not a second typeface. **Numerics, counts, and pill labels
are monospaced** (`caption`, `pillLabel`, `pillCount`) so digits do not jitter as
counts tick. Sizes are tight (10.5–14px) because the surface is tiny: `caption`
10.5 for dense metadata, `body` 12 for rows, `headline` 13 / `headlineLarge` 14
for section titles. Use `*Emphasis` (semibold) for the active/selected item in a
pair, never bold-as-decoration.

## Layout

Spacing follows `IslandSpacing` (2 · 4 · 6 · 8 · 12 · 16 · 20 · 24). Inside the
pill and dense rows, stay in the low steps (`xxs`–`md`); panels and settings
cards use `lg`–`xxxl`. The ladder is monotonic — pick the nearest step, do not
interpolate.

Opacity is also a ladder (`IslandOpacity`: 0.045 · 0.08 · 0.22 · 0.42 · 0.55 ·
0.78 · 0.88 · 1.0). Use it to express **state**, not to tint: `hairline`/`faint`
for separators and pressed washes, `dim`/`muted` for inactive content, `soft`/
`strong` for secondary/primary text de-emphasis.

## Elevation & Depth

Two shadows only (`IslandShadow`): `subtle` (black 18%, radius 4, y 2) for
resting chrome, and `elevated` (black 36%, radius 22, y 12) for the expanded
overlay panel that floats out of the notch. A third dynamic form, `pulse(tint:
phase:)`, breathes a **status-tinted** glow (radius 5, no offset) to signal an
active/waiting session — it is the only shadow that carries color, and its color
is always a status tint.

Motion is spring-first (`IslandMotion`): `microSpring` for taps/toggles,
`popSpring` for the notch open/close, `bouncySpring` for playful count changes,
`breathe` (0.7s ease, autoreversing) for the waiting pulse. Prefer a spring token
over an ad-hoc `easeInOut`.

## Shapes

Corners follow `IslandRadius` (6 · 8 · 10 · 12 · 16 · `pill` 999). The collapsed
island is a **full pill** (`pill`); rows use `md` (10); panels and settings cards
use `lg`–`xl` (12–16). The closed-pill and opened-surface silhouettes are custom
shapes (`V6ClosedPillShape`, `OpenedIslandSurfaceShape`) that continue the
notch's curvature — new floating elements should echo that rounding, not
introduce sharp corners.

## Components

Each entry in the front matter is a real surface, composed only from the tokens
above:

- **closedPill** — the resting island: `ink` surface, `paper` label, `pill`
  radius, monospaced `pillLabel`. This is the app's most-seen element; keep it
  the highest-contrast, most legible thing on screen.
- **countBadge** — the numeric session count on the pill: monospaced `pillCount`
  in `paper`, so digits stay aligned as the count changes.
- **statusIndicator** — a 6px dot whose fill is the session's status tint
  (`running` shown as the default). The dot *is* the status signal; do not also
  recolor the surrounding text. Its per-state variants —
  **statusIndicatorRunning / Completed / WaitingForApproval / WaitingForAnswer**,
  plus **statusIndicatorWaitingAggregate** for the collapsed roll-up — are the
  same dot resolved to each `SessionPhase`'s tint
  (`IslandDesignPalette.Status.tint(for:)`).
- **sessionRow** — a row in the expanded panel: `ink` surface, `paper` text,
  `body` type, `md` radius, `lg` padding. The status tint appears only on the
  row's indicator, not its background.
- **settingsCard** — a card in Settings/Appearance: same ink-on-paper, larger
  `lg` radius and `xl` padding for a calmer, less dense context.
- **agentTile{Codex,ClaudeCode,Cursor,Gemini}** — the appearance-preview swatch
  for an agent, filled with that agent's `brand*` default. These are *fallbacks*:
  render an agent's own `brandColorHex` when it supplies one, and only fall back
  to these so the preview is never colorless.

`primary` is an alias for `running` — Open Island's key accent is the active-state
blue, not a separate brand hue. There is deliberately no additional primary color.

Variants (hover, pressed, selected) are expressed by moving along the **opacity**
and **motion** ladders, not by introducing new colors: a hover is a `faint`
paper wash + `microSpring`; a selection swaps `body` → `bodyEmphasis`.

## Do's and Don'ts

**Do**
- Keep everything ink-on-paper; let status tints be the *only* saturated color.
- Use one status tint per state, and put it on the indicator/glyph, not the whole
  surface.
- Reach for the nearest ladder step (spacing / radius / opacity / type) before
  adding a raw value.
- Mirror any token change in both this file and the Swift enum it came from.
- Use monospaced type for anything numeric so it does not jitter.

**Don't**
- Don't introduce a decorative or brand color that has no status meaning.
- Don't express "inactive" as a new hue — use low-opacity paper instead.
- Don't hardcode a hex, size, or radius that a token already names.
- Don't slot a value between two ladder steps unless it carries a distinct,
  documented meaning.
- Don't use bold or a second typeface for emphasis — use the `*Emphasis`
  (semibold) token.
