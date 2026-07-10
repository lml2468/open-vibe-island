---
type: Journal
title: "Journal: bridge-subagent-state"
description: Extracted BridgeServer's Claude subagent/task pure cores into BridgeSubagentState/BridgeTaskState static namespaces with direct tests, preserving the subtle emit-vs-no-emit contracts; second BridgeServer god-object cut, −71 LOC
tags: ["dedup", "bridge", "session-metadata", "correctness"]
timestamp: 2026-07-10T05:35:00Z
slug: bridge-subagent-state
source: self
---

# Journal: bridge-subagent-state

Second cut on the #3 BridgeServer god-object, following `BridgeMetadataMerging` (#50).
See `.octospec/tasks/bridge-subagent-state/brief.md` (r1, approved).

## What was done

Moved the pure array-transform cores of BridgeServer's 6 Claude subagent/task methods
into `BridgeSubagentState` (adding/removing/clearingAll/removingStale) and
`BridgeTaskState` (creating/updatingStatus/replacingID/parseRealTaskID) static
namespaces over `ClaudeSessionMetadata`, returning `ClaudeSessionMetadata?` (nil = no
change). The 6 methods became thin fetch→transform→emit wrappers via a new
`emitClaudeMetadata` helper; `Date.now` and `UUID()` are read in the wrappers and
passed into the pure funcs. BridgeServer: 2,536 → 2,465 LOC (−71; cumulative −254 with
#50). `bridge-transport-invariants` unaffected — cores are pure, emit stays on the
serial path in the wrappers.

## Verification

- New `BridgeSubagentTaskStateTests` (10): add-dedup/remove-nil-when-absent/clearAll,
  stale-timeout boundary (nil startedAt never stale; injected now; nil-when-none),
  task create/updateStatus (match/no-match/nil-status), replacingID nil-when-absent,
  and parseRealTaskID across all 3 response shapes (nested string+number→Int,
  top-level keys, regex/trimmed string, empty/nil). First direct coverage of this
  logic + the parser.
- TDD trail: `red:` (82eb5e4) stubbed both namespaces → all 10 failed on assertion;
  Green (6cd2ec4) filled the cores + delegated; `git diff red..green -- Tests/` = 0.
- Independent Verify (fresh context) PASS, no findings — confirmed pure-core
  byte-equivalence and all SIX emit contracts preserved, including the two traps:
  updateTask emits UNCONDITIONALLY after the taskId guard (task-not-found AND
  unknown-toolName fall-through, the latter via the new `else { updatedMetadata =
  metadata }`), and replaceTaskID guards tempID BEFORE parsing. Purity verified (no
  self/localState/emit/queue in the namespace). Gate green: `harness.sh ci` (524
  tests), exit 0.

## Learning

- **When extracting a state mutator, the emit/no-emit decision is the contract — map
  it to the return type, and byte-check the fall-through.** These methods emit a
  broadcast event only on certain paths (remove/stale/clear only if something changed;
  replaceTaskID only if tempID present and realID parseable) — but updateTask emits
  UNCONDITIONALLY once past its input guards, including when the task isn't found and
  even for an unknown toolName (an implicit else-fall-through in the original). Encoding
  "changed?" as `ClaudeSessionMetadata?` (nil = skip emit) captures the conditional
  cases cleanly, but the unconditional-emit case must stay unconditional in the wrapper
  — do NOT "helpfully" make it nil-skip. The subtlest bug here would be turning
  updateTask's task-not-found path into a no-emit; the test + Verify byte-diff guard it.
- **Lift impurities (clock, UUID) into the thin wrapper, keep the core a pure function
  of its inputs.** `Date.now`→`now:` and `UUID().uuidString`→`id:` let the stale-timeout
  boundary and task-id assignment be tested deterministically, while the wrapper reads
  the real clock/uuid once. Third instance of this seam in the campaign
  (HookGroupSanitizer closure, reducer-arm inout, now clock/uuid params).
- **BridgeServer god-object remaining is now just the headline `AgentHookHandler`
  per-agent protocol** (~1,100 LOC of handle*Hook). That one is genuinely entangled
  (40× emit / 37× send / per-agent pending* dicts) and needs a context/delegate seam +
  a multi-agent C+A test net (only Claude is well-covered end-to-end) — a much larger,
  riskier slice than the two pure-core extractions (#50, this). The pure tiers are now
  done; what's left is the structural handler decomposition.
