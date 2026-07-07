---
type: Task
title: "Task: bridge-security"
description: Harden the local bridge — write timeout, socket peer-auth/permissions, and forward-compatible event decoding
tags: ["bridge", "security", "ipc", "concurrency", "correctness"]
timestamp: 2026-07-07T12:12:39Z
# --- octospec extension fields ---
slug: bridge-security
upstream: self
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-07T12:29:53Z
---

# Task: bridge-security

> First slice of the `arch-quality-audit` discovery (see
> `.octospec/tasks/arch-quality-audit/discovery.md`). Chosen first because it is
> small, high-impact, and testable without touching UI or the god objects wholesale.
> Scope is deliberately narrow: three concrete robustness/security defects on the
> app↔hook transport. Other audit slices (reducer purity, installer safety, dedup,
> perf, UI decomposition, quality gates) are separate future tasks.

## Goal
Make the local bridge resilient to a stuck/hostile peer and to schema drift,
without changing the wire protocol for well-behaved clients:

1. **Bounded writes.** `writeAll` (`BridgeTransport.swift:425`) currently
   `usleep(1_000)`-spins forever on `EAGAIN`/`EWOULDBLOCK` with no deadline. Because
   all server writes run on the single serial `bridge.server` queue, one reader whose
   receive buffer fills (slow, crashed-but-not-closed, or malicious) wedges the entire
   bridge — every client, every hook dispatch, all state processing. Give `writeAll` a
   deadline; on timeout, throw so the caller can drop that one client instead of
   hanging the whole server.

2. **Local peer trust + socket permissions.** The control socket has no peer
   authentication and is created without explicit permissions. The **primary** socket
   is under a user-owned dir (`~/Library/Application Support/OpenIsland/bridge.sock`),
   but the **legacy** socket at `/tmp/open-island-<uid>.sock`
   (`BridgeTransport.swift:19`) is world-traversable. Any local process that connects
   can send `resolvePermission` / `answerQuestion` / `process*Hook` and approve/deny an
   agent's tool use or spoof sessions. Constrain access: verify the connecting peer's
   uid via `LOCAL_PEERCRED`/`getpeereid` and reject non-matching peers, and create both
   sockets with `0600`-equivalent restriction (chmod the socket and/or its parent dir).

3. **Forward-compatible event decoding.** `AgentEvent.init(from:)`
   (`AgentEvent.swift:286`) has no `default`/unknown-type fallback. A newer hook binary
   emitting an event type this app doesn't know throws `DecodingError`, which on the
   observer stream (`AppModel.swift:1203` `for try await`) ends the loop and forces a
   full reconnect — and on the server read path drops the batch. Decode unknown event
   types into a safe, ignorable sentinel (or skip the single envelope) so one unknown
   event neither kills the stream nor tears down the connection.

## Background
- Transport: newline-delimited JSON envelopes over `AF_UNIX` (`BridgeCodec`,
  `BridgeTransport.swift`). Server is `BridgeServer` (`@unchecked Sendable`, one serial
  `bridge.server` queue). Clients: `LocalBridgeClient` (observer), `BridgeCommandClient`
  (hooks).
- **Fail-open is a hard invariant** (CLAUDE.md): if the app/bridge is down or misbehaves,
  the agent must run unchanged. The write-timeout and unknown-event changes must preserve
  this — a dropped client or skipped event must never surface an error to the agent's hook
  process.
- `disableSocketSigPipe` + `makeSocketNonBlocking` already exist; the socket is bound via
  `withUnixSocketAddress`. `SO_NOSIGPIPE` is set, so a peer that closes is handled; the gap
  is a peer that stays open but never drains.
- Verified during discovery: no `chmod`/`fchmod`/`getpeereid`/`LOCAL_PEERCRED` anywhere in
  `Sources/OpenIslandCore/`.

## Load-bearing list
<!-- Existing behaviors/contracts this change touches. Derive from discovery.md. -->
- **`writeAll(_:to:)`** — `BridgeTransport.swift:425-446`. Used by both server broadcast
  (`BridgeServer.swift:2593,2606`) and `LocalBridgeClient.send` (`:79-96`). Changing its
  signature/throwing behavior affects every write site.
- **Serial `bridge.server` queue discipline** — the `@unchecked Sendable` safety of
  `BridgeServer` rests on all mutation happening on this one queue; a write timeout must
  not introduce a second concurrency domain or a `queue.sync`-from-queue deadlock.
- **Socket bind/create path** — `BridgeSocketLocation.defaultURL` (`:13`) and `legacyURL`
  (`:19`), `withUnixSocketAddress` (`:365`), and the server's `bind`/`listen` setup. Both
  the primary and legacy sockets must remain reachable by the app's own hook binaries.
- **Peer connection acceptance** — `BridgeServer.acceptPendingClients` (`:205-225`) and
  `registerClient`; a uid check is added on accept.
- **Command dispatch trust** — the commands a peer may send (`resolvePermission`,
  `answerQuestion`, `process*Hook`); these are the assets the peer check protects.
- **`AgentEvent` Codable** — `AgentEvent.swift:286` (`init(from:)`) and `:328` (`encode`),
  plus `EventType`/`CodingKeys` (`:255-284`). Round-trip must stay stable for all 12 known
  types.
- **Observer stream loop** — `AppModel.swift:1203-1214`: must keep flowing across an
  unknown event; must still reconnect on genuine disconnect.
- **`fail-open` hook paths** — `OpenIslandHooksCLI.swift`, `BridgeCommandClient` (a write
  timeout on the client side must degrade to "no directive", not an error to the agent).

## Out of scope
- Refactoring / decomposing the `BridgeServer` god object (separate audit slice).
- Any wire-format/protocol-version change or negotiation (`BridgeHello.protocolVersion`
  stays as-is; only additive/back-compatible behavior).
- Read-side batch fairness / yielding (`readAvailableData` starvation, discovery #15) —
  related but separate; not touched here.
- TLS/auth for the Watch/iPhone HTTP endpoint (discovery #29) — different transport.
- Removing `@unchecked Sendable` or enabling strict-concurrency flags (quality-gates slice).
- Backpressure redesign / bounded per-client send queues beyond the timeout-and-drop fix.

## Acceptance
<!-- Machine-checkable where possible. -->
- **A1 — write timeout.** A new `OpenIslandCoreTests` case proves `writeAll` (or its server
  wrapper) throws/returns within a bounded time when the peer never drains (simulate with a
  socketpair whose read end is never consumed and whose send buffer is filled), instead of
  looping indefinitely. The offending client is dropped; a second, healthy client still
  receives subsequent broadcasts.
- **A2 — peer uid check.** A test connects from the same uid and succeeds; the accept path
  rejects a connection whose `getpeereid` uid ≠ the server's uid (unit-test the predicate
  even if a cross-uid socket can't be forged in CI). No regression: the app's own
  `LocalBridgeClient`/`BridgeCommandClient` still connect and exchange messages end-to-end.
- **A3 — socket permissions.** After the server binds, both the primary and legacy socket
  files (or their containing dir) are not group/other-accessible — assert mode bits via
  `FileManager`/`stat` in a test.
- **A4 — forward-compatible decode.** A test feeds an envelope with an unknown `type` string
  through `AgentEvent` decoding and the decoder does **not** throw; the unknown event is
  ignored/sentinel and the stream continues. All 12 known event types still round-trip
  (`encode`→`decode` equality) — extend existing `BridgeCodec`/event tests.
- **A5 — fail-open preserved.** A test (or reasoned assertion backed by code) confirms that a
  write timeout on `BridgeCommandClient` and an unknown/late event both degrade to
  no-directive / no-error for the hook process — the agent is never blocked or errored.
- **A6 — gate green.** `zsh scripts/harness.sh ci` (lint-strings → docs → `swift test` →
  `swift build`) passes; no new warnings.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
