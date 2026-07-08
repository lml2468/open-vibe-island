---
type: Task
title: "Task: watch-auth-hardening"
description: Constant-time bearer-token comparison and higher-entropy pairing code for the Watch/iPhone HTTP endpoint
tags: ["security", "auth", "watch", "ipc"]
timestamp: 2026-07-08T10:55:00Z
# --- octospec extension fields ---
slug: watch-auth-hardening
upstream: arch-quality-audit-r2 (discovery finding #20; testable part of #1)
source: self
revision: 1
approvals: []
---

# Task: watch-auth-hardening

> First slice of the `arch-quality-audit-r2` discovery. Small, self-contained,
> high-confidence auth hardening on the Watch/iPhone bridge. The transport-level
> exposure (finding #1, plain HTTP / no TLS) is **deliberately out of scope** —
> it needs a maintainer threat-model decision and is a much larger change.

## Goal

Harden the two authentication weaknesses in `WatchHTTPEndpoint` that need no
architectural decision:

1. **Constant-time bearer-token comparison.** `authenticateRequest` currently
   does `validTokens.contains(token)` (`WatchHTTPEndpoint.swift:621`), an ordinary
   `Set<String>` membership whose per-element `String` equality short-circuits on
   the first differing byte — a timing side-channel on token verification. Replace
   it with a comparison that runs in time independent of where the mismatch
   occurs and does not early-return on the first non-matching stored token.

2. **Higher-entropy pairing code.** The pairing code is 4 digits
   (`pairingCodeLength = 4`, `:116`) → 10,000 combinations, generated at
   `regeneratePairingCodeUnsafe` (`:646`). Even with the existing `PairingThrottle`
   (5 failures → 60s lockout ⇒ ~7,200 guesses/hr) the full space is exhaustible in
   under a day. Widen the keyspace by increasing the code length, via a pure,
   unit-testable generator.

Both are pure defense-in-depth improvements to the auth path; neither changes the
HTTP endpoints, the token format (`UUID`), or the SSE/pairing wire shapes.

## Background

- The Watch endpoint (`Sources/OpenIslandCore/WatchHTTPEndpoint.swift`) is a
  minimal HTTP/1.1 server over `NWListener` + Bonjour with 4 routes
  (`/pair`, `/events`, `/resolution`, `/status`). `/pair` exchanges the displayed
  numeric code for a bearer token; the other authenticated routes verify that
  token via `authenticateRequest`.
- The codebase already has the right testable-seam precedent here:
  `PairingThrottle` (`:491`) is a pure value type with injectable time, unit-tested
  in `Tests/OpenIslandCoreTests/WatchNotificationRelayTests.swift`. This slice
  follows the same shape — extract pure helpers and test them directly.
- Related rule to read during Implement: `bridge-transport-invariants`
  (fail-closed authorization is distinct from fail-open hooks — a verification
  path must not leak and must default-deny), captured by the earlier
  `bridge-security` slice. The Watch endpoint is the network sibling of that
  hardening.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`WatchHTTPEndpoint.authenticateRequest`** (`:615-622`) — the sole bearer-token
  verification path for `/events`, `/resolution`, `/status`. `[auth] [security]`
- **`WatchHTTPEndpoint.validTokens`** (`Set<String>`, `:130`) — the set the compare
  iterates; behavior (valid token accepted, unknown rejected) must be preserved.
  `[auth]`
- **`WatchHTTPEndpoint.regeneratePairingCodeUnsafe` + `pairingCodeLength`**
  (`:116,:645-650`) — pairing-code generation; the `/pair` handler compares
  `request.code == currentPairingCode` (`:458`), which stays a code-vs-code check.
  `[security]`
- **The `/pair` → token → authenticated-route flow** — end-to-end auth behavior
  must be unchanged for a legitimate client. `[ipc] [auth]`

## Out of scope
- **TLS / transport encryption (finding #1).** Tokens/prompts/cwd still travel
  cleartext; this slice does not add TLS or cert pinning — that is a separate brief
  pending the maintainer's threat-model decision. **This slice must not create the
  impression #1 is resolved.**
- **The `PairingThrottle` state machine** — already sound; not modified beyond
  what the length change requires (it needs none).
- **Changing the token format** (stays `UUID().uuidString`) or any HTTP
  route/JSON shape.
- **The Unix-socket bridge** (`BridgeServer`/`BridgeTransport`) — already hardened
  in `bridge-security`.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — constant-time equality helper exists and is correct.** A dedicated
  internal helper (e.g. `WatchHTTPEndpoint.constantTimeEquals(_:_:)`) returns
  `true` for identical strings and `false` for: a difference in the first byte, a
  difference in the last byte, and unequal lengths; empty-vs-empty is `true`.
  *(Testable: direct unit test of the helper. Fails first — the helper does not
  exist.)*
- **A2 — token verification uses the helper and does not early-return across the
  token set, with behavior preserved.** An internal verification seam (e.g.
  `isAuthorizedToken(_:)` or `authenticateRequest` made testable) accepts a token
  present in `validTokens`, rejects an absent token, and rejects a missing/
  malformed `Authorization` header. The set scan accumulates over all stored
  tokens (no `contains`/first-match early-out). *(Testable: unit test asserting
  accept/reject outcomes through the internal seam. Fails first — currently uses
  `validTokens.contains`.)*
- **A3 — pairing code has a pure generator and a larger keyspace.** A pure
  generator (e.g. `WatchHTTPEndpoint.makePairingCode(length:)`) returns a string
  of exactly the requested length containing only decimal digits; the configured
  `pairingCodeLength` is increased to at least 6 (≥ 1,000,000 combinations).
  *(Testable: unit test on generator length + charset, and that the configured
  length is ≥ 6. Fails first — no generator, length is 4.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): this is the gate
  itself, not a unit test.)*

> Note on the timing guarantee: A1 tests the **correctness** of the constant-time
> helper and A2 tests that the auth path **uses** it; the timing-invariance
> property itself is provided by construction (compare visits every byte / every
> stored token), not asserted by a wall-clock test — wall-clock timing tests are
> flaky and are intentionally not part of the gate.

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
