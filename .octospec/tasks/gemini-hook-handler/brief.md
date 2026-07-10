---
type: Task
title: "Task: gemini-hook-handler"
description: Proof-of-concept extraction of handleGeminiHook into a GeminiHookHandler behind a minimal synchronous AgentHookContext protocol with a dispatchPrecondition off-queue guard; establishes the AgentHookHandler seam on the simplest agent without touching shared interaction state
tags: ["dedup", "bridge", "app-model", "correctness"]
timestamp: 2026-07-10T05:50:00Z
# --- octospec extension fields ---
slug: gemini-hook-handler
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — AgentHookHandler PoC)
source: self
revision: 1
approvals: []
---

# Task: gemini-hook-handler

> Proof-of-concept for the AgentHookHandler seam (the scout recommended a single-agent
> PoC over full 5-handler extraction — full extraction relocates the shared-interaction
> coupling without removing it, needs a ~550-LOC test net, and risks the serial-queue
> invariant). Gemini is the ideal PoC: smallest handler (88 LOC), already socket-tested,
> zero shared pending*/resolve involvement. Independent branch off `origin/main`. See
> `.octospec/tasks/gemini-hook-handler/discovery.md`.

## Goal

Extract `handleGeminiHook` + its 3 private helpers into a standalone `GeminiHookHandler`
behind a minimal **synchronous** context protocol, establishing the seam a future
per-agent decomposition would reuse — without touching any shared state:
```swift
protocol AgentHookContext: AnyObject {
    func emit(_ event: AgentEvent)
    func send(_ envelope: BridgeEnvelope, to clientID: UUID)
    func hasSession(id: String) -> Bool
    func session(id: String) -> AgentSession?   // localState read only
}
protocol AgentHookHandler {
    associatedtype Payload
    func handle(_ payload: Payload, from clientID: UUID, context: AgentHookContext)
}
struct GeminiHookHandler: AgentHookHandler { /* verbatim body via context */ }
```
BridgeServer conforms to `AgentHookContext` (exposing its existing emit/send/hasSession
+ a new `session(id:)` returning `localState.session(id:)`), holds a `GeminiHookHandler`,
and `handleGeminiHook` becomes:
`dispatchPrecondition(condition: .onQueue(queue)); geminiHandler.handle(payload, from: clientID, context: self)`.
The `dispatchPrecondition` is the off-queue guard the scout called for — it makes the
single-serial-queue invariant *enforced* rather than assumed. The Gemini metadata/jump
merge stays inline in the handler (Gemini was never routed through a merged* helper);
`mergeJumpTargetPreservingExistingResolvedFields` is already static and called directly.

## Deliberately NOT in scope
- **The other 4 handlers** (Claude/Codex/OpenCode/Cursor) — this PoC extracts Gemini
  ONLY; the decision to do more is deferred until the seam is proven.
- **The shared pending*/`resolvePermission`/`answerQuestion`/`removeClient` paths** —
  Gemini touches none; they stay entirely in BridgeServer.
- **A heterogeneous handler registry** — `GeminiHookHandler` is a single concrete
  stored property; no existential/registry (that's the full-extraction concern).
- No wire-format/reducer/socket-lifecycle change.

## Background
- **Injected rule:** `bridge-transport-invariants` (load-bearing, gates
  `BridgeServer.swift`). The context is SYNCHRONOUS (no async) → no off-queue path
  introduced; `emit` still does `localState.apply`+`broadcast` on the serial queue.
  The added `dispatchPrecondition(.onQueue(queue))` strengthens the invariant. No
  framing/model change. `AgentHookContext: AnyObject` so `self` is passed by reference.
- Coverage: `GeminiHooksTests` (~9 tests incl. 3 socket-driven BridgeServer
  round-trips) exercises the handler end-to-end → behavior-neutral proof.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `AgentHookContext`/`AgentHookHandler` protocols + `GeminiHookHandler`** — the
  handler body must reproduce `handleGeminiHook`'s exact per-case emit/send sequence
  and the ensure/sync helper logic. `[bridge]`
- **BridgeServer** — conforms to `AgentHookContext` (new `session(id:)` = localState
  read; emit/send/hasSession already exist), holds the handler, delegates
  `handleGeminiHook` with the on-queue precondition; removes the 3 Gemini helpers.
  `[bridge]`
- **The Gemini hook path** — unchanged behavior (same events emitted, same acks).
  `[bridge]`

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — GeminiHookHandler maps events correctly (via a fake context).** Driving
  `GeminiHookHandler.handle` with a fake `AgentHookContext` that records emitted
  events + sent envelopes: `sessionStart` → a `.sessionStarted` (tool .geminiCLI) +
  an `.acknowledged` send; `beforeAgent` → `.activityUpdated(.running)`; `afterAgent`
  → `.sessionCompleted`; `sessionEnd` → `.sessionCompleted(isSessionEnd:true)`;
  `notification` → `.activityUpdated` with the current phase. *(Testable: direct unit
  test with a fake context. Fails first — the handler type does not exist / is stubbed.)*
- **A2 — sync helpers preserved.** With a session present in the fake context,
  `beforeAgent` triggers the jump-target + metadata sync (a `.jumpTargetUpdated`
  and/or `.geminiSessionMetadataUpdated` emitted when they differ; none when equal);
  `ensureGeminiSessionExists` emits `.sessionStarted` only when the session is absent.
  *(Testable: direct unit test. Fails first.)*
- **A3 — BridgeServer delegates behind the guarded seam; behavior preserved.**
  `handleGeminiHook` calls `geminiHandler.handle(..., context: self)` after
  `dispatchPrecondition(.onQueue(queue))`; the 3 Gemini helpers are removed from
  BridgeServer; BridgeServer conforms to `AgentHookContext`. The existing
  `GeminiHooksTests` (incl. the socket round-trips) pass unchanged. *(Testable: the
  existing suite + A1/A2 are the proof.)*
- **A4 — invariant enforced, not weakened.** The context protocol is synchronous (no
  `async`); `emit`/`send` remain the only state-touching context methods; the handler
  runs on the serial queue (asserted by `dispatchPrecondition`). *(Verifiable by
  review against `bridge-transport-invariants`.)*
- **A5 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): gate + GeminiHooksTests
  are the behavior-neutral proof for the delegation; A1/A2 are the new seam tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
