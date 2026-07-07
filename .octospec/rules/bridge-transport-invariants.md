---
type: Rule
title: Bridge transport invariants
description: Rules for changing the app↔hook Unix-socket bridge — fail-open hooks vs fail-closed auth, bounded writes, and forward-compatible framing.
tags: ["bridge", "ipc", "transport", "security", "concurrency"]
timestamp: 2026-07-07T12:46:16Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: bridge-transport-invariants
tier: repo
priority: 85
load_bearing: true
inject_when:
  paths:
    - "Sources/OpenIslandCore/BridgeServer.swift"
    - "Sources/OpenIslandCore/BridgeTransport.swift"
    - "Sources/OpenIslandCore/LocalBridgeClient.swift"
    - "Sources/OpenIslandCore/BridgeCommandClient.swift"
    - "Sources/OpenIslandCore/AgentEvent.swift"
    - "Sources/OpenIslandHooks/OpenIslandHooksCLI.swift"
  touches: ["bridge", "ipc", "transport"]
source: self
supersedes: []
---

# Bridge transport invariants

The app↔hook bridge is newline-delimited JSON over `AF_UNIX`, served by a single
serial queue inside `BridgeServer`. When changing any transport code, preserve
these invariants.

## Fail-open hooks vs. fail-closed auth (do not conflate)

- **Hooks fail open**: if the app/bridge is down or errors, the agent must run
  unchanged. A hook CLI that cannot reach the bridge (or gets any send error)
  emits no directive and exits silently. Never make an agent block or error
  because of a bridge problem.
- **Authorization fails closed**: the control socket carries privileged commands
  (`resolvePermission`, `answerQuestion`, `process*Hook`) that can approve/deny an
  agent's tool use. A peer that cannot be verified (uid indeterminate, or ≠ the
  server's uid) must be **rejected**, not admitted. These are compatible: a
  rejected peer receives no directive, which *is* the fail-open outcome.
- Concretely: keep the `getpeereid`/`isTrustedLocalPeer` default-deny check on
  accept and the `0600` `chmod` on every bound socket (including the legacy
  `/tmp` path). Do not add an auth path that admits on error.

## Bounded, non-blocking writes

- All server writes share one serial queue. Any blocking write **must** be
  bounded by a deadline (`writeAll(..., timeout:)`, default `bridgeWriteTimeout`).
  A peer that connects but never drains its receive buffer must be dropped, not
  allowed to spin/wedge the whole bridge. On timeout, throw so the caller drops
  that one client (`BridgeServer.send` already does).
- Do not reintroduce an unbounded `EAGAIN` spin loop.

## Forward-compatible framing

- Put forward-compatibility at the **discriminator**, not the model enum. Decode a
  tagged union's `type` as a `String`; an unknown value throws
  `BridgeTransportError.unknownMessageType`, and `BridgeCodec.decodeLines` skips
  just that frame. One unknown frame from a newer peer must never end the NDJSON
  stream or force a reconnect.
- Keep model enums (e.g. `AgentEvent`) **closed** — do not add an `.unknown` case
  that ripples into every exhaustive switch. Genuinely malformed JSON must still
  be a hard error (`.malformedEnvelope`); only well-formed-but-unknown frames are
  skipped.
- Preserve the frame-size cap (`BridgeCodec.maxFrameByteCount`) — it bounds both
  complete frames and the unterminated tail against OOM.
