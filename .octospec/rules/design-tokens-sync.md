---
type: Rule
title: Design tokens and DESIGN.md stay in sync
description: Any change to a design-token source must be mirrored in DESIGN.md, and vice versa.
tags: ["design", "design-tokens", "visual-identity"]
timestamp: 2026-07-07T10:26:37Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: design-tokens-sync
tier: repo
priority: 70
load_bearing: false
inject_when:
  paths:
    - "DESIGN.md"
    - "Sources/OpenIslandApp/Design/DesignTokens.swift"
    - "Sources/OpenIslandApp/Design/BrandPalette.swift"
    - "Sources/OpenIslandApp/IslandDesignPalette.swift"
    - "Sources/OpenIslandApp/V6ClosedPillShape.swift"
  touches: ["design", "design-tokens", "visual-identity"]
source: self
supersedes: []
---

# Design tokens and DESIGN.md stay in sync

`DESIGN.md` (root, in the [google-labs-code/design.md](https://github.com/google-labs-code/design.md)
format) is the agent-readable single source of truth for Open Island's visual
identity. Its token values are a **mirror** of the Swift token enums that
actually ship. The two must never drift.

## The two sides

- **What ships** — the Swift enums:
  - `V6Palette` (ink / paper) in `Sources/OpenIslandApp/V6ClosedPillShape.swift`
  - `IslandDesignPalette.Status` (status tints) in `Sources/OpenIslandApp/IslandDesignPalette.swift`
  - `BrandPalette` (agent brand defaults) in `Sources/OpenIslandApp/Design/BrandPalette.swift`
  - `IslandTypography` / `IslandRadius` / `IslandSpacing` (and the other ladders)
    in `Sources/OpenIslandApp/Design/DesignTokens.swift`
- **What agents read** — the YAML front matter in root `DESIGN.md`.

## Rule

- When you change a value in any of the token sources above, **update the matching
  key in `DESIGN.md`** in the same change — and the reverse: a `DESIGN.md` token
  edit must be reflected in the Swift enum, because the enum is what renders.
- Colors in `DESIGN.md` are hex; convert faithfully from the Swift `Color`:
  - `0xNN / 255.0` components → the two-hex-digit value directly.
  - fractional `Color(red:green:blue:)` (0–1) → `round(component * 255)` per
    channel. (e.g. `0.55 → 0x8c`.)
- Keep the token **name/path** identical on both sides where one exists, so
  `{colors.x}` / `{rounded.x}` references in `DESIGN.md` stay resolvable.
- Adding a new token: add it to the Swift ladder (keep it monotonic — do not slot
  between existing steps without a distinct semantic meaning) **and** to
  `DESIGN.md`.

## How to check (Verify phase)

A change is compliant when, for every token touched, the `DESIGN.md` hex/value
equals the value computed from the Swift source. A quick check: recompute each
changed color's hex from its Swift RGB and diff against `DESIGN.md`; there must be
zero mismatches. Do not mark Verify green while any token differs between the two.
