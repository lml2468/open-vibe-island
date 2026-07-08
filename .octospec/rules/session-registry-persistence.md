---
type: Rule
title: Session registry persistence
description: Per-agent session registries share one persistence layer — don't reintroduce per-type copies; keep the on-disk format stable.
tags: ["registry", "persistence", "dedup", "session-discovery"]
timestamp: 2026-07-08T08:48:23Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: session-registry-persistence
tier: repo
priority: 75
load_bearing: false
inject_when:
  paths:
    - "Sources/OpenIslandCore/SessionRegistryStore.swift"
    - "Sources/OpenIslandCore/ClaudeSessionRegistry.swift"
    - "Sources/OpenIslandCore/CursorSessionRegistry.swift"
    - "Sources/OpenIslandCore/OpenCodeSessionRegistry.swift"
  touches: ["registry", "persistence"]
source: self
supersedes: []
---

# Session registry persistence

The per-agent session registries (`ClaudeSessionRegistry`,
`CursorSessionRegistry`, `OpenCodeSessionRegistry`, `CodexSessionStore`) persist
`[Record]` to JSON. They all share **one** persistence implementation.

## One implementation

- Route all load/save through `SessionRegistryStore.load`/`save`. Do NOT re-inline
  the `JSONDecoder`/`JSONEncoder` + `.atomic` write into a registry type — that's
  the copy-paste this slice removed. A new per-agent registry should be a thin
  type that owns only its `defaultFileURL` and record type and delegates
  persistence.
- Prefer a shared **helper** the named types delegate to over a generic base
  class, so each type keeps its own `defaultFileURL` / `init` / record type and
  the sole consumer (`SessionDiscoveryCoordinator`) needs no changes.

## Stable on-disk format

- The wire format is fixed: `.iso8601` dates, `[.prettyPrinted, .sortedKeys]`,
  atomic write, missing file → `[]`. Changing any of these breaks existing user
  installs — don't, unless you add a migration.
- When you touch the persistence layer, prove format stability by decoding a
  hand-authored fixture in the **old** on-disk format (unsorted keys, iso8601
  dates), not just a round-trip through the new code.
- Record structs (`*TrackedSessionRecord`) own their own `CodingKeys`; that's a
  payload concern, separate from this persistence layer.
