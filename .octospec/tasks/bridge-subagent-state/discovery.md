---
type: Note
title: "Discovery: bridge-subagent-state"
description: Extract BridgeServer's Claude subagent-lifecycle + task-tracking pure cores into BridgeSubagentState/BridgeTaskState static namespaces over ClaudeSessionMetadata; lift the clock/UUID impurities into wrappers; add direct tests for the untested paths
tags: ["discovery"]
# --- octospec extension fields ---
timestamp: 2026-07-10T05:05:00Z
slug: bridge-subagent-state
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — slice 2, subagent/task tier)
source: self
---

# Discovery: bridge-subagent-state

> Read-only Discover output. Second cut on the #3 BridgeServer god-object, following
> the `BridgeMetadataMerging` (#50) precedent: extract the pure core of the Claude
> subagent/task state methods into static namespaces, keeping the fetch→emit
> orchestration in BridgeServer. Single slice with Red→Green (the extraction itself
> creates the testable surface, same as #50) — NOT a separate C+A, because the pure
> funcs become directly testable as they're extracted.

## Relevant methods (BridgeServer.swift, current lines)
All six share the shape: `guard var metadata = localState.session(id:)?.claudeMetadata
else { return }` → mutate `metadata.activeSubagents`/`activeTasks` → `emit(.claudeSessionMetadataUpdated(...timestamp: .now))`. None touch `pending*`/`clients`/socket/`queue` — verified transport-free.
- `addSubagent(_:toSession:)` (1992-2009) — dedup by agentID (removeAll), append; **always emits**.
- `removeSubagent(agentID:fromSession:)` (2011-2031) — removeAll matching; **emits only if count changed** (no-op guard 2018).
- `cleanUpStaleSubagents(forSession:)` (2038-2062) + `subagentStaleTimeout=3*60` (2036) — guard non-empty; remove where `now - startedAt > timeout` (nil startedAt never stale); reads `Date.now` (2044); **emits only if count changed**.
- `clearAllActiveSubagents(fromSession:)` (2113-2130) — guard non-empty; removeAll; **always emits** (when non-empty).
- `updateTask(from:toolName:sessionID:) -> String?` (2134-2178, `@discardableResult`) — see contract below; reads `UUID()` (2148).
- `replaceTaskID(sessionID:tempID:response:)` (2181-2230) — see contract below.

## Exact emit contracts (the load-bearing nuance — must preserve byte-for-byte)
- **`updateTask`** (only ever called with toolName `"TaskCreate"`/`"TaskUpdate"` — callers gate at 721/729):
  - TaskCreate: `guard case .string(title) = input["subject"] ?? input["description"] else { return nil }` (**no emit** on missing subject). Else id = `input["id"].string ?? UUID().uuidString`, status = `input["status"]` parsed or `.pending`; append; **emit**; return id.
  - TaskUpdate: taskId = `input["taskId"] ?? input["task_id"] ?? input["id"]` (.string); `guard let taskId else { return nil }` (**no emit**). If idx found AND status parses → set status. **Emit unconditionally after the taskId guard** (even if task not found or status absent — a no-op emit). Return nil.
- **`replaceTaskID`**: `guard metadata + firstIndex(tempID) exists else return` (**no emit** if tempID absent — checked BEFORE parsing). Parse realID from response (3 shapes: nested `task.id`/`task.taskId` string-or-number; top-level `taskId`/`task_id`/`id`; string via `#"(?<=Task #)\S+"#` regex then trimmed-nonempty). `guard realID nonempty else return` (**no emit**). Set `activeTasks[idx].id = realID`; **emit**.

## Data types (ClaudeHooks.swift)
- `ClaudeSubagentInfo` (211-231): agentID, agentType?, summary?, taskDescription?, startedAt?.
- `ClaudeTaskInfo` (233-247): id, title, status (`Status`: pending/inProgress="in_progress"/completed).
- `ClaudeSessionMetadata` (249-313): `var activeSubagents: [ClaudeSubagentInfo] = []`, `var activeTasks: [ClaudeTaskInfo] = []`. Value type; `isEmpty` counts both arrays.
- The arrays are mutated ONLY here; `BridgeMetadataMerging.mergedClaudeMetadata` PRESERVES them verbatim (161-162) — so this extraction composes cleanly with #50 (merge preserves, state funcs edit).

## Proposed extraction (pure static, over ClaudeSessionMetadata)
`enum BridgeSubagentState`:
- `adding(_:to:) -> ClaudeSessionMetadata` (dedup+append; always-change)
- `removing(agentID:from:) -> ClaudeSessionMetadata?` (nil = unchanged)
- `clearingAll(from:) -> ClaudeSessionMetadata?` (nil = already empty)
- `removingStale(from:now:timeout:) -> ClaudeSessionMetadata?` (nil = none removed; empty→nil)

`enum BridgeTaskState`:
- `creating(title:id:status:in:) -> ClaudeSessionMetadata` (append)
- `updatingStatus(taskID:status:in:) -> ClaudeSessionMetadata` (status optional; find idx, set if both present; returns possibly-unchanged — the wrapper emits unconditionally, matching TaskUpdate)
- `replacingID(tempID:realID:in:) -> ClaudeSessionMetadata?` (nil = tempID not found)
- `parseRealTaskID(from: ClaudeHookJSONValue?) -> String?` (the 3-shape parser — pure, the highest-value test target)

Wrappers keep: the `localState` fetch, the JSON parsing of tool input (TaskCreate/TaskUpdate keys), the emit-vs-no-emit decisions, `Date.now`/`UUID()` (lifted → passed as `now:`/`id:`), and return values. Byte-behavior identical.

## Test coverage — thin (extraction adds the direct net)
- `BridgeMetadataMergingTests:101` tests only merge PRESERVATION of the arrays, not add/remove/clear/stale/update/replace.
- `ClaudeHooksTests:585` drives subagentStop but asserts phase/summary, not `activeSubagents`.
- No test asserts emitted `activeSubagents`/`activeTasks` contents. **Uncovered → new direct Red tests**: add-dedup, remove-not-found-no-change, stale-timeout boundary (nil startedAt never stale; injected now), clearAll, task create (subject/description fallback, id fallback, status parse/default), task update (key fallback, not-found no-op, status update), replaceTaskID all 3 response shapes (nested object string+number, top-level, regex string, empty→nil).

## Risks & unknowns
- **The emit-on-no-change TaskUpdate contract** is the trap: TaskUpdate emits even when the task isn't found. The pure `updatingStatus` must return the (possibly unchanged) metadata and the wrapper must emit unconditionally after the taskId guard — do NOT convert it to nil-skip-emit. Verify byte-diffs the wrapper emit sites.
- **Guard ordering in replaceTaskID**: tempID existence is checked BEFORE parsing realID. Keep that order (parse is pure/no-side-effect, but preserve to be safe): wrapper guards tempID, then parses, then guards realID.
- **Impurity lifting**: `Date.now`→`now:` (cleanUpStaleSubagents wrapper reads Date.now once, passes in), `UUID().uuidString`→ the wrapper computes `id` and passes to `creating`. Behavior-neutral.
- `bridge-transport-invariants` gates BridgeServer.swift — pure funcs have no queue/socket, so unaffected; emit stays on the serial path in the wrappers.
- No human decision — scope settled (extract the pure cores + parser; wrappers keep parse/emit/guards).
