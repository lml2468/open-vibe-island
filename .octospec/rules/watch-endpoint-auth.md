---
type: Rule
title: Watch endpoint auth
description: The Watch/iPhone HTTP endpoint verifies tokens in constant time with no set-scan early-out, fails closed, and uses a high-entropy pairing code.
tags: ["security", "auth", "watch", "ipc", "timing"]
timestamp: 2026-07-08T11:20:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: watch-endpoint-auth
tier: repo
priority: 80
load_bearing: true
inject_when:
  paths:
    - "Sources/OpenIslandCore/WatchHTTPEndpoint.swift"
    - "Sources/OpenIslandCore/WatchNotificationRelay.swift"
  touches: ["watch", "auth"]
source: self
supersedes: []
---

# Watch endpoint auth

`WatchHTTPEndpoint` is a network-reachable (Bonjour/LAN) HTTP surface whose bearer
token can approve/deny an agent's tool use. Its auth path must fail closed and not
leak via timing. This mirrors the Unix-socket `bridge-transport-invariants`
(fail-closed authorization) for the *network* sibling.

## Constant-time verification, all the way through

- Compare tokens with `constantTimeEquals` (visits every byte, folds the length
  check into the accumulator, single verdict — no early return on content
  mismatch). Do NOT use `==` on secret material.
- The **set scan** must not early-out either. Verify membership with a
  non-short-circuit fold that always visits every stored token —
  `matched = constantTimeEquals(candidate, token) || matched` (compare on the
  **left**). Never `validTokens.contains(token)`, `first(where:)`, or `a || b`
  with the compare on the right — each leaks match position via timing.

## Fail closed

- Absent or malformed `Authorization` header → deny. Empty token set → deny.
  Unverified token → deny. No auth path may admit on error. A rejected request
  simply gets no directive (which is also the fail-open outcome for the agent).

## Pairing code entropy

- Keep `pairingCodeLength >= 6` (>= 1,000,000 combinations) and generate it with
  the pure `makePairingCode(length:)` helper (digits only, exact length). The
  `PairingThrottle` + short expiry are necessary but not sufficient — the keyspace
  itself must not be trivially exhaustible. The code is typed into the companion
  client app (separate repo); coordinate a length change with that input field.

## What this rule does NOT cover

- Transport encryption. The endpoint is still plain HTTP over Bonjour — tokens,
  prompts, and cwd travel cleartext (discovery finding #1). Adding TLS/pinning (or
  an explicit "same-LAN trust accepted" decision) is a separate, larger change.
  Do not let a token/pairing improvement read as "the Watch bridge is secure."
