---
type: Task
title: "Task: reducer-metadata-arm-tests"
description: Add direct reducer characterization tests for the 5 SessionState.apply metadata arms (Codex/Claude/Gemini/OpenCode + Cursor for uniformity) as the safety net for collapsing them into one helper
tags: ["reducer", "session-state", "test-coverage", "correctness"]
timestamp: 2026-07-09T14:05:00Z
# --- octospec extension fields ---
slug: reducer-metadata-arm-tests
upstream: arch-quality-audit-r2 (discovery finding #10, cluster C — reducer arm collapse, test-net slice)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T14:37:08Z
---

# Task: reducer-metadata-arm-tests

> Slice C of the reducer-arm C+A (slice A = collapse the 5 arms, blocked on this).
> **Test-only** — adds the direct reducer coverage that makes the collapse safe.
> Independent branch off `origin/main`. See
> `.octospec/tasks/reducer-metadata-arm-tests/discovery.md`.

## Goal

The 5 `SessionState.apply` metadata arms (`SessionState.swift:189-232`) are
identical modulo the metadata keypath, but only Cursor's is covered end-to-end
(`cursorStopClearsCurrentToolMetadata`). Codex/Claude/Gemini/OpenCode have **no
direct reducer test**. Before slice A collapses all 5 into one helper, add direct
reducer characterization tests pinning each arm's four load-bearing properties, so
a collapse that drops the guard, forgets `isEmpty→nil`, mis-wires a keypath, or
breaks the timestamp fails loudly.

Add, for each of the 5 arms (Cursor included for uniform coverage of the future
helper), reducer tests asserting:
1. **set** — a non-empty metadata payload sets `session.Xmetadata`.
2. **isEmpty → nil** — an empty metadata payload clears the field to `nil`.
3. **updatedAt** — the arm sets `session.updatedAt` to `payload.timestamp` (a
   distinct fixed value, proving the deterministic caller-supplied timestamp).
4. **unknown sessionID → no-op** — applying to a state without that session
   inserts nothing and changes nothing.

## Not a Red→Green slice (why)

Characterization tests of already-correct behavior — they pass on `origin/main` as
written, so there is no failing-first step (marked `N/A(test-first)`). Verify's job
is the inverse: confirm each assertion is DISCRIMINATING (would fail if slice A's
collapse regressed that property), not tautological. Same shape as the manager
`manager-roundtrip-tests` net.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`SessionState.apply` metadata arms** (Codex/Claude/Gemini/OpenCode/Cursor) —
  the tests target these directly via `SessionState(sessions:).apply(event)`.
  `[reducer] [session-state]`
- **The tests only** — NO production change in this slice.

## Out of scope
- **Any production change** — tests exclusively. If a test reveals a real bug (it
  should not — these arms are simple), that is a separate slice.
- **The arm collapse itself** (slice A, blocked on this net).
- Non-metadata reducer arms (sessionStarted/activityUpdated/permission/question/
  completed/jumpTarget/actionableStateResolved) — already covered elsewhere; not
  this slice.

## Acceptance
<!-- Test-only slice: items are the coverage that must exist and pass on main. -->
- **A1 — Codex arm** (`.sessionMetadataUpdated`): non-empty sets `codexMetadata`;
  empty → nil; `updatedAt == payload.timestamp`; unknown sessionID → no session
  created / state unchanged. *(Passes on main.)*
- **A2 — Claude arm** (`.claudeSessionMetadataUpdated`): same four properties over
  `claudeMetadata`. *(Passes on main.)*
- **A3 — Gemini arm** (`.geminiSessionMetadataUpdated`): same four over
  `geminiMetadata`. *(Passes on main.)*
- **A4 — OpenCode arm** (`.openCodeSessionMetadataUpdated`): same four over
  `openCodeMetadata`. *(Passes on main.)*
- **A5 — Cursor arm** (`.cursorSessionMetadataUpdated`): same four over
  `cursorMetadata` (direct reducer test for uniformity; complements the existing
  end-to-end Cursor test). *(Passes on main.)*
- **A6 — discriminating + gate green.** Each test asserts properties that would
  FAIL if the arm stopped setting the field, stopped nilling on empty, stopped
  bumping updatedAt, or dropped the unknown-id guard — i.e. not tautological.
  `swift build` + `swift test` pass under the repo gate (warnings-as-errors +
  `swiftlint --strict`). *(N/A(test-first): coverage-only; Verify confirms the
  assertions are real, not a failing-first trail.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
