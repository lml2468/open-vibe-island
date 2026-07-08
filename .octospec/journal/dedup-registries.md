---
type: Journal
title: "Journal: dedup-registries"
description: Extracted a shared SessionRegistryStore for the 4 near-identical per-agent session persistence layers, keeping public APIs and on-disk format stable
tags: ["refactor", "dedup", "registry", "persistence"]
timestamp: 2026-07-08T08:48:23Z
slug: dedup-registries
source: self
---

# Journal: dedup-registries

Sixth implemented slice of the `arch-quality-audit` discovery (finding #6,
registry dimension). A pure persistence-layer extraction — no behavior or
format change.

## What was done

`ClaudeSessionRegistry`, `CursorSessionRegistry`, `OpenCodeSessionRegistry`, and
`CodexSessionStore` had byte-identical `load()`/`save()` bodies (JSON, `.iso8601`
dates, `[.prettyPrinted, .sortedKeys]`, `.atomic` write, dir auto-create,
missing-file → `[]`). Extracted that into one shared `SessionRegistryStore` (a
helper enum with generic `load<Record>`/`save<Record>`); each registry's
`load`/`save` collapsed from ~11 lines to a 3-line delegation.

**Design:** chose a shared helper enum over a generic base class / subclassing.
That keeps every registry type's `defaultFileURL`, `init(fileURL:fileManager:)`,
and record type exactly as-is — so `SessionDiscoveryCoordinator` (the sole
consumer) compiled with **zero** changes, and the on-disk format is provably
unchanged rather than argued.

The record structs (`*TrackedSessionRecord`) were left untouched — their per-agent
`CodingKeys` are payload concerns, not persistence.

## Verification

- New `SessionRegistryStoreTests`: `CodexSessionStore` round-trip (previously
  **untested**), missing-file → empty, legacy on-disk format decodes (hand-authored
  unsorted-key JSON), shared store writes ISO-8601 + sorted keys and round-trips.
- Existing `ClaudeSessionRegistryTests` / `CursorSessionRegistryFirstSeenTests` /
  `OpenCodeSessionRegistryTests` pass unchanged (format identity = A5).
- Full gate green: `harness.sh ci` (382 tests) with warnings-as-errors + SwiftLint
  strict, exit 0. Net LOC down (registries −58, replaced by one ~50-line file).

## Learning

- **A shared helper beats a generic base class when the goal is API stability.**
  Subclassing a generic `SessionRegistry<Record>` would have forced changes to
  each type's `static defaultFileURL` / init-default plumbing; a stateless helper
  enum that the existing types delegate to removed the duplication with a
  zero-churn public surface. Prefer this shape for "same logic, different
  type/filename" persistence.
- **Prove format stability with a legacy fixture, not just a round-trip.** A
  round-trip through the new code can't catch an encoder-policy drift; decoding a
  hand-authored file in the *old* on-disk format does. Captured in the
  `session-registry-persistence` rule.
