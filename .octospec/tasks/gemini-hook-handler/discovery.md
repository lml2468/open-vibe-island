---
type: Note
title: "Discovery: gemini-hook-handler"
description: Proof-of-concept extraction of handleGeminiHook into a GeminiHookHandler behind a minimal synchronous AgentHookContext protocol with a dispatchPrecondition off-queue guard; establishes the AgentHookHandler seam without touching shared interaction state
tags: ["discovery"]
timestamp: 2026-07-10T05:45:00Z
# --- octospec extension fields ---
slug: gemini-hook-handler
upstream: arch-quality-audit-r2 (discovery finding #3, god-object BridgeServer — AgentHookHandler PoC)
source: self
---

# Discovery: gemini-hook-handler

> Read-only Discover output. PROOF-OF-CONCEPT for the AgentHookHandler seam (the
> scout recommended a single-agent PoC over full extraction — full extraction
> relocates the shared-interaction coupling without removing it and needs a ~550-LOC
> test net). Gemini is the ideal PoC: smallest handler, already socket-tested, and
> has NO shared pending*/resolvePermission/answerQuestion involvement.

## Relevant code (BridgeServer.swift)
- `handleGeminiHook(_:from:)` (1333-1420, 88 LOC) — switch over GeminiHookEventName
  (sessionStart/beforeAgent/afterAgent/sessionEnd/notification). Each case:
  ensure/sync helpers → `emit(...)` → `send(.response(.acknowledged), to: clientID)`.
- Helpers `ensureGeminiSessionExists` (1422-1442), `synchronizeGeminiJumpTarget`
  (1444-1467), `synchronizeGeminiMetadata` (1469-1499) — all Gemini-private, called
  only by handleGeminiHook.
- Dispatch: `handle(_:from:)` case `.processGeminiHook(payload)` (501-502) →
  `handleGeminiHook(payload, from: clientID)`.
- **Dependencies the handler touches** (→ the context surface):
  - `emit(_ event: AgentEvent)` (2348) — `localState.apply` + `broadcast`.
  - `send(_ envelope: BridgeEnvelope, to: UUID)` (2357).
  - `hasSession(id:) -> Bool` (2353) — localState OR stateSnapshot.
  - `localState.session(id:)` read (in syncJumpTarget/syncMetadata/notification-phase).
  - `Self.mergeJumpTargetPreservingExistingResolvedFields(incoming:existing:)` (1920,
    already `static`) — callable directly, no context needed.
  - `GeminiSessionMetadata` merge is inline (1475-1481) — NOTE it duplicates the
    logic `BridgeMetadataMerging` uses for other agents but Gemini was never routed
    through a merged* helper (Gemini has no hookEvent-based tool clearing). Leave the
    inline merge in the handler for this PoC (behavior-neutral move).
  - NO pending*/clients-sweep/resolve involvement — verified. Clean.
- Concurrency: everything runs on the serial `queue` (63) via `handle`←`readAvailableData`.
  `queueKey` (64) already exists for on-queue assertions.

## Proposed seam (minimal, synchronous)
```swift
// The surface BridgeServer exposes to an extracted handler. SYNCHRONOUS ONLY
// (no async) so handler code cannot hop off the serial queue.
protocol AgentHookContext: AnyObject {
    func emit(_ event: AgentEvent)
    func send(_ envelope: BridgeEnvelope, to clientID: UUID)
    func hasSession(id: String) -> Bool
    func session(id: String) -> AgentSession?   // localState read
}

protocol AgentHookHandler {
    associatedtype Payload
    func handle(_ payload: Payload, from clientID: UUID, context: AgentHookContext)
}

struct GeminiHookHandler: AgentHookHandler {
    func handle(_ payload: GeminiHookPayload, from clientID: UUID, context: AgentHookContext) {
        // verbatim handleGeminiHook body, with emit/send/hasSession/session routed
        // through `context`, and jump-target merge via the existing static func.
    }
}
```
BridgeServer:
- conforms to `AgentHookContext` (exposing the existing private emit/send/hasSession
  + a new `session(id:)` that returns `localState.session(id:)`).
- `handleGeminiHook` becomes: `dispatchPrecondition(condition: .onQueue(queue));
  geminiHandler.handle(payload, from: clientID, context: self)` — where
  `geminiHandler` is a stored `GeminiHookHandler()`. The `dispatchPrecondition` is the
  off-queue guard the scout called for (traps in debug if handler runs off-queue).
- The 3 Gemini helpers move INTO GeminiHookHandler as private methods taking the
  context.

## Contracts & blast radius
- **Behavior-neutral**: the handler body is verbatim; emit/send order per case
  preserved; the same events with `.now` timestamps. `hasSession`/`session` reads go
  through the context but resolve to the same localState/stateSnapshot.
- `bridge-transport-invariants` (load-bearing): the context is SYNCHRONOUS, so no
  off-queue path is introduced; emit still does localState.apply+broadcast on the
  queue. The `dispatchPrecondition` makes the invariant enforced, not just assumed —
  a strengthening. `AgentHookContext: AnyObject` (class-bound) so BridgeServer passes
  `self` without copying.
- Coverage: `GeminiHooksTests` (333 LOC, ~9 tests, incl. 3 socket-driven BridgeServer
  round-trips) exercises the handler end-to-end → behavior-neutral proof.
- Out of scope: the other 4 handlers, the shared pending*/resolve/removeClient paths
  (Gemini touches none), and any change to the 4 non-Gemini dispatch cases.

## Risks & unknowns
- **`session(id:)` on the context**: BridgeServer's `hasSession` also checks
  `stateSnapshot`; but the Gemini handler's `localState.session(id:)` reads only
  localState (for phase + jumpTarget/metadata merge). The context `session(id:)` must
  return `localState.session(id:)` ONLY (not stateSnapshot) to preserve behavior —
  `hasSession` keeps its OR-snapshot logic separately. Two distinct methods.
- **Associated-type protocol + stored handler**: `AgentHookHandler` has an
  associatedtype (Payload), so it can't be stored as an existential without care; but
  `GeminiHookHandler` is a concrete stored property — fine. (For the PoC, don't build
  a heterogeneous handler registry; that's the full-extraction concern.)
- **TDD**: the handler body is a verbatim relocation covered by GeminiHooksTests, so
  this is closer to `N/A(test)` — BUT the new seam (context protocol + the
  dispatchPrecondition + the handler routing) is genuinely new and worth a direct
  test: a small test that drives GeminiHookHandler with a fake AgentHookContext
  (recording emitted events) proving the sessionStart→sessionStarted mapping and the
  syncMetadata merge. That is a valid failing-first (the handler type doesn't exist).
  Recommend: Red = the fake-context handler test + a stub handler; Green = real body.
  Behavior-neutrality of the delegation proven by GeminiHooksTests staying green.
- No human decision — scope settled (Gemini only; minimal sync context; guard).
