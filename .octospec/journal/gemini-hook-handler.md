---
type: Journal
title: "Journal: gemini-hook-handler"
description: Proof-of-concept extraction of handleGeminiHook into a GeminiHookHandler behind a minimal synchronous AgentHookContext seam with a dispatchPrecondition on-queue guard; establishes the per-agent handler pattern on the simplest agent
tags: ["dedup", "bridge", "correctness"]
timestamp: 2026-07-10T06:05:00Z
slug: gemini-hook-handler
source: self
---

# Journal: gemini-hook-handler

AgentHookHandler proof-of-concept on the #3 BridgeServer god-object — the scout
recommended a single-agent PoC over full 5-handler extraction (which relocates the
shared-interaction coupling rather than removing it, needs a ~550-LOC test net, and
risks the serial-queue invariant). See `.octospec/tasks/gemini-hook-handler/brief.md`
(r1, approved).

## What was done

Introduced a minimal **synchronous** `AgentHookContext` protocol (emit/send/hasSession/
session) + an `AgentHookHandler` protocol, and moved `handleGeminiHook` + its 3 helpers
verbatim into a standalone `GeminiHookHandler` that talks to the server only through the
context. BridgeServer conforms to `AgentHookContext` (emit/send/hasSession relaxed
private→internal, bodies unchanged; new `session(id:)` = localState-only read), holds a
stateless `GeminiHookHandler`, and `handleGeminiHook` became a guarded delegate:
`dispatchPrecondition(condition: .onQueue(queue)); geminiHookHandler.handle(payload,
from: clientID, context: self)`. BridgeServer: 2,465 → 2,319 LOC (−146; cumulative −400
with #50/#54). Gemini was chosen because it's the smallest handler, already has socket
round-trip tests, and touches none of the shared pending*/resolve state.

## Verification

- New `GeminiHookHandlerTests` (6): drive `GeminiHookHandler` with a fake
  `AgentHookContext` recording emitted events + sent envelopes — A1 per-event mapping
  (all 5 Gemini events), A2 ensure-session-only-when-absent. First direct (socket-free)
  test of the Gemini handler logic.
- TDD trail: `red:` (ddc85f6) declared the protocols + a no-op stub handler → all 6
  failed on assertion; Green (849a6ad) filled the body + wired the seam; `git diff
  red..green -- Tests/` = 0.
- Independent Verify (fresh context) PASS, no findings — all 5 event cases verbatim
  (incl. sessionEnd's isInterrupt/isSessionEnd flags + reason-map summary, and
  notification's `currentPhase = session(id:)?.phase ?? .completed`), `session(id:)`
  correctly localState-only (not stateSnapshot), the sole visibility change, the
  transport invariant enforced (synchronous context, `dispatchPrecondition`, no
  DispatchQueue/Task/async introduced), other 4 handlers + shared paths untouched. Gate
  green: `harness.sh ci` (530 tests); GeminiHooksTests socket round-trips pass unchanged.

## Learning

- **When a scout says "full extraction relocates the coupling," a single-agent PoC is
  the right way to buy the decision cheaply.** Full 5-handler extraction would have
  needed a 550-LOC test net (3 of 5 handlers lack socket coverage) and a `canResolve`
  handler-loop to replace the cross-agent pending-dict probing — ending with the same
  coupling behind a protocol. Extracting ONLY Gemini (no shared state, already tested)
  proves the `AgentHookContext` seam and the on-queue-guard pattern for ~0.5 day and
  zero shared-state risk, so the *next* decision (do more? which agent?) is now
  evidence-based rather than speculative.
- **Enforce a concurrency invariant at the new seam, don't just preserve it.** The
  load-bearing rule is "all handler code on the single serial queue"; extracting a
  handler into a separate type is exactly where a future edit could add an `async`
  context method or an off-queue callback and silently race the pending* dicts. Two
  guards make it structural: (1) the context protocol is **synchronous only** (no async
  method can be added without a visible protocol change), and (2)
  `dispatchPrecondition(.onQueue(queue))` at the delegate entry traps loudly in debug if
  the handler ever runs off-queue. A refactor that touches a concurrency invariant
  should leave the invariant *more* enforced than it found it.
- **BridgeServer god-object status:** the two pure tiers (#50 metadata merge, #54
  subagent/task) + this Gemini handler PoC are done (−400 LOC total). What remains is
  the DECISION on whether to extract the other 4 handlers — and per the scout that is
  gated on: a socket test net for Codex/Cursor/OpenCode (~550 LOC) and a design for the
  shared `resolvePermission`/`answerQuestion`/`removeClient` cross-agent fan-out (the
  `canResolve` handler-loop). The seam pattern is now proven and reusable when/if that
  trigger arrives (e.g. adding a 6th agent). Recommend NOT extracting the remaining
  handlers speculatively — the coupling doesn't shrink, only moves.
