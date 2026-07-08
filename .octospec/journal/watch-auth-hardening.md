---
type: Journal
title: "Journal: watch-auth-hardening"
description: Constant-time bearer-token comparison and higher-entropy pairing code for the Watch/iPhone HTTP endpoint
tags: ["security", "auth", "watch", "ipc", "timing"]
timestamp: 2026-07-08T11:20:00Z
slug: watch-auth-hardening
source: self
---

# Journal: watch-auth-hardening

First implemented slice of the `arch-quality-audit-r2` discovery (findings #20 +
the testable part of #1). Two decision-free auth-path fixes on the Watch/iPhone
bridge; the transport-level exposure (plain HTTP / no TLS) was deliberately left
out of scope pending a maintainer threat-model decision.

## What was done

One file (`WatchHTTPEndpoint.swift`), no wire/route/token-format change.

1. **Constant-time bearer-token compare (#20).** `authenticateRequest` used
   `validTokens.contains(token)`, whose per-element `String` equality
   short-circuits on the first differing byte — a timing side-channel. Split into
   three pure static seams: `constantTimeEquals` (length folded into a XOR
   accumulator, visits every common byte, single verdict), `isAuthorizedToken`
   (non-short-circuit scan — `constantTimeEquals(...) || matched` with the call on
   the left so every stored token is always visited), and `bearerToken` (header
   extraction). `authenticateRequest` now routes through them; the old `contains`
   is gone. Fails closed on absent/malformed header or empty set.
2. **Higher-entropy pairing code (#20).** `pairingCodeLength` 4 → 6 (10k → 1M
   combinations) via a pure `makePairingCode(length:)` generator; the old inline
   generation in `regeneratePairingCodeUnsafe` now delegates to it. Stale
   "4-digit" comments/docs refreshed.

## Verification

- New `WatchAuthHardeningTests` (13 `@Test`): A1 constant-time correctness
  (identical / first-byte / last-byte / unequal-length / empty), A2 verification
  seam (present accept, absent/empty-set/missing/malformed reject, case-insensitive
  header), A3 generator length+charset and `pairingCodeLength >= 6`.
- TDD trail: seams committed as wrong-value stubs in `red:` so the tests failed on
  **assertions** (compiled, not compile-errors); Green filled only the stubs and
  did not touch the tests (`git diff red..green -- Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS; full gate green: `harness.sh ci`
  (395 tests, 49 suites) under warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Constant-time membership needs two properties, not one.** A timing-safe
  *compare* is worthless if the *set scan* around it early-outs — `set.contains`,
  `first(where:)`, or `a || b` with the compare on the right all leak match
  position. The fix is a non-short-circuit fold (`compare(x) || acc`, compare on
  the left) that always visits every candidate. Captured as the new
  `watch-endpoint-auth` rule.
- **In a compiled language, a valid TDD "Red" adds the seam as a wrong-value
  stub.** A test that references a nonexistent symbol fails to *compile*, which
  octospec rejects as an invalid Red (it must fail on the assertion, for the right
  reason). Committing stubs that return `false`/`nil`/`""` makes the suite compile
  and fail on assertions; Green then only edits the stub bodies, so the red→green
  test diff is provably empty (no test-faking).
- **Scope honesty matters when a fix is adjacent to a bigger one.** Widening the
  pairing keyspace and constant-timing the compare are real improvements but do
  **not** close the cleartext-transport hole (#1). The brief's Out-of-scope and
  the code comments say so explicitly, so the slice can't be mistaken for
  "the Watch bridge is now secure."
- **Cross-repo soft-compat:** the pairing code is typed into the companion
  iPhone/Watch client (separate repo). 4→6 assumes that input field isn't
  hard-capped at 4 — flagged at Plan; if the client caps it, coordinate there.
