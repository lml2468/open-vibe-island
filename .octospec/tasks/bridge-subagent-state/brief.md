---
type: Task
title: "Task: bridge-subagent-state"
description: Extract BridgeServer's Claude subagent-lifecycle + task-tracking pure cores into BridgeSubagentState/BridgeTaskState static namespaces over ClaudeSessionMetadata, lifting the clock/UUID impurities into the wrappers, with direct tests for the untested paths
tags: ["dedup", "bridge", "session-metadata", "correctness"]
timestamp: 2026-07-10T05:10:00Z
# --- octospec extension fields ---
slug: bridge-subagent-state
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — slice 2, subagent/task tier)
source: self
revision: 1
approvals: []
---

# Task: bridge-subagent-state

> Second cut on the #3 BridgeServer god-object, following the `BridgeMetadataMerging`
> (#50) precedent. Independent branch off `origin/main`. See
> `.octospec/tasks/bridge-subagent-state/discovery.md`.

## Goal

BridgeServer's six Claude subagent-lifecycle + task-tracking methods
(`addSubagent`/`removeSubagent`/`cleanUpStaleSubagents`/`clearAllActiveSubagents`/
`updateTask`/`replaceTaskID`) each decompose into a pure array-transform over
`ClaudeSessionMetadata` + a thin fetch→emit orchestration. Extract the pure cores into
two static namespaces (OpenIslandCore) and reduce the BridgeServer methods to
delegating wrappers:
```swift
enum BridgeSubagentState {
    static func adding(_ subagent: ClaudeSubagentInfo, to m: ClaudeSessionMetadata) -> ClaudeSessionMetadata
    static func removing(agentID: String, from m: ClaudeSessionMetadata) -> ClaudeSessionMetadata?   // nil = unchanged
    static func clearingAll(from m: ClaudeSessionMetadata) -> ClaudeSessionMetadata?                  // nil = already empty
    static func removingStale(from m: ClaudeSessionMetadata, now: Date, timeout: TimeInterval) -> ClaudeSessionMetadata?  // nil = none removed
}
enum BridgeTaskState {
    static func creating(title: String, id: String, status: ClaudeTaskInfo.Status, in m: ClaudeSessionMetadata) -> ClaudeSessionMetadata
    static func updatingStatus(taskID: String, status: ClaudeTaskInfo.Status?, in m: ClaudeSessionMetadata) -> ClaudeSessionMetadata
    static func replacingID(tempID: String, realID: String, in m: ClaudeSessionMetadata) -> ClaudeSessionMetadata?  // nil = tempID absent
    static func parseRealTaskID(from response: ClaudeHookJSONValue?) -> String?
}
```
The wrappers keep: the `localState` fetch guard, the tool-input JSON parsing
(TaskCreate/TaskUpdate keys), the exact emit-vs-no-emit decisions, the `Date.now`/
`UUID()` reads (lifted → passed as `now:`/`id:`), and the return values. Byte-behavior
identical. This shrinks BridgeServer and makes the array logic + the task-ID parser
directly unit-testable for the first time.

## Deliberately NOT in scope
- **The `pending*` dictionaries / `dropPendingClaudeContexts` / handleClaudeHook
  orchestration** — a separate tier; the wrappers stay in BridgeServer and callers are
  unchanged.
- **The emit/localState/queue orchestration** — stays in the wrappers (transport).
- **The `AgentHookHandler` per-agent protocol** — the later, larger slice.
- No wire-format / reducer / socket change.

## Background
- **Injected rule:** `bridge-transport-invariants` (load-bearing, gates
  `BridgeServer.swift`). The extracted cores are pure (no queue/socket/state) — the
  single-serial-queue + fail-open/closed invariants are untouched; emit stays on the
  serial path in the wrappers. No framing/model change.
- These arrays are mutated ONLY here and PRESERVED verbatim by
  `BridgeMetadataMerging.mergedClaudeMetadata` (#50) — so this composes cleanly.
- Coverage today: none asserts the array contents (only merge-preservation +
  incidental subagentStop). This slice adds the direct net.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `BridgeSubagentState` / `BridgeTaskState`** — pure cores; the change/no-change
  signals (Optional nil) must exactly mirror the current emit guards. `[bridge] [session-metadata]`
- **BridgeServer's 6 methods** — become fetch→transform→emit wrappers preserving the
  exact emit-vs-no-emit contracts (esp. TaskUpdate's unconditional emit after the
  taskId guard; replaceTaskID's tempID-before-parse guard order). `[bridge]`
- **The Claude subagent/task hook paths** — unchanged behavior (which events emit,
  what metadata results). `[bridge] [session-metadata]`

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — subagent add/remove/clear.** `adding` dedups by agentID then appends;
  `removing` returns nil when the agentID is absent (no change) else the trimmed
  metadata; `clearingAll` returns nil when already empty else emptied. *(Testable:
  direct unit tests. Fail first — stubs.)*
- **A2 — stale removal with injected now.** `removingStale` removes subagents whose
  `startedAt` is older than `timeout` relative to the passed `now`; a nil `startedAt`
  is never stale; returns nil when nothing is removed. Pin the boundary
  (just-under vs just-over timeout). *(Testable. Fails first.)*
- **A3 — task create/update.** `creating` appends a `ClaudeTaskInfo(id:title:status:)`;
  `updatingStatus` sets the status of the matching task when both taskID matches and
  status is non-nil, and returns the metadata unchanged when the task is absent or
  status is nil (the wrapper still emits — preserving TaskUpdate's contract).
  *(Testable. Fails first.)*
- **A4 — replaceTaskID + parseRealTaskID.** `replacingID` returns nil when tempID is
  absent, else metadata with that task's id set to realID. `parseRealTaskID` extracts
  from: nested `task.id`/`task.taskId` (string AND number→Int), top-level
  `taskId`/`task_id`/`id`, a `"Task #<x>"` regex string, a trimmed non-empty string;
  returns nil for empty/none. *(Testable — the 3-shape parser is the highest-value
  target. Fails first.)*
- **A5 — BridgeServer delegates; behavior preserved.** The 6 methods delegate to the
  namespaces, preserving the exact emit-vs-no-emit contracts (byte-diff at Verify);
  `Date.now`/`UUID()` lifted into the wrappers; callers unchanged. The existing
  `ClaudeHooksTests` (incl. subagentStop) pass unchanged. *(Testable: existing suite +
  A1-A4 are the proof.)*
- **A6 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + existing bridge
  suites are the behavior-neutral proof for the wrapper relocation; A1-A4 are the new
  tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
