---
type: Journal
title: "Journal: bridge-security"
description: Hardened the local bridge — write timeout, same-user socket auth/permissions, forward-compatible event decoding
tags: ["bridge", "security", "ipc", "concurrency", "correctness"]
timestamp: 2026-07-07T12:46:16Z
slug: bridge-security
source: self
---

# Journal: bridge-security

First implemented slice of the `arch-quality-audit` discovery.

## What was done

Three narrow, high-impact robustness/security fixes on the app↔hook Unix-socket
transport, plus tests. No wire-protocol change; no `BridgeServer` decomposition.

1. **Bounded writes** — `writeAll` (`BridgeTransport.swift`) gained a monotonic
   `DispatchTime` deadline (default `bridgeWriteTimeout = 5s`). Previously it
   `usleep`-spun on `EAGAIN` forever; since all server writes run on one serial
   `bridge.server` queue, a peer that connects but never drains could wedge the
   entire bridge. On timeout it now throws `.writeTimedOut`; the existing
   `BridgeServer.send` already drops a client on any write error, so the stuck
   peer is dropped while healthy peers keep receiving — no server redesign.

2. **Same-user socket boundary** — the control socket carries privileged
   commands (`resolvePermission` / `answerQuestion` / `process*Hook`). Added
   `peerEffectiveUID` / `isTrustedLocalPeer` (via `getpeereid`, default-deny on
   indeterminate uid) enforced in `acceptPendingClients`, and a `chmod 0600` on
   both the primary and legacy sockets in `bindListener` (bind → chmod → listen,
   so perms are set before any connection can be accepted). The legacy
   `/tmp/open-island-<uid>.sock` was the real exposure; the primary socket
   already lived under a user-owned Application Support dir.

3. **Forward-compatible decoding** — the envelope / event / command / response
   discriminators now decode as `String` and throw a distinguishable
   `.unknownMessageType`; `BridgeCodec.decodeLines` **skips** just that frame.
   A newer hook binary's unknown event type no longer throws `DecodingError`,
   which had ended the observer `for try await` loop (`AppModel.swift:1203`) and
   forced a full reconnect. Genuinely malformed JSON still throws
   `.malformedEnvelope`. `AgentEvent`'s enum stayed closed, so no ripple into the
   four exhaustive switches across the app.

## Verification

- New tests (`Tests/OpenIslandCoreTests/`): `BridgeWriteTimeoutTests`,
  `BridgeForwardCompatDecodingTests`, `BridgeSocketSecurityTests`.
- Full gate green: `swift build` + `swift test` (355 tests, 44 suites) via
  `scripts/harness.sh ci`, exit 0, no new warnings.

## Learning

- **Fail-closed auth vs. fail-open hooks are distinct and compatible.** The repo's
  "hooks fail open" invariant is about the *agent-facing* path (bridge down →
  agent runs unchanged). It does **not** license a fail-open *authorization* path:
  a peer whose uid can't be verified must be denied. A rejected peer simply
  receives no directive, which is itself the fail-open outcome. Encoded as a
  candidate rule (`bridge-transport-invariants`).
- **Forward compatibility belongs at the discriminator, not the enum.** Skipping
  an unknown *tagged* frame in the codec keeps model enums closed (no `.unknown`
  case rippling into every exhaustive switch) while making the NDJSON stream
  survive a newer peer.
- **Toolchain:** `swift test` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (swift-testing ships with Xcode, not CommandLineTools). Already in env memory.
