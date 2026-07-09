---
type: Journal
title: "Journal: config-manifest-store"
description: Extracted the byte-identical manifest persistence + hooks-binary resolution helpers shared across the 5 hook installation managers into a generic ConfigManifestStore; kept per-manager orchestration and the Claude/Codex-only legacy resolvedManifestURL in place
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T12:45:00Z
slug: config-manifest-store
source: self
---

# Journal: config-manifest-store

Slice A of the C+A plan (slice C = `manager-roundtrip-tests`, #44). The safe
manager-tier dedup from the `arch-quality-audit-r2` cluster-B manager tier, landing
on the round-trip test net. See `.octospec/tasks/config-manifest-store/brief.md`
(r1, approved).

## What was done

The 5 hook installation managers (Claude/Codex/Cursor/Gemini/Kimi) each carried
three duplicated pieces differing only by the per-manager `Manifest` type:
`loadManifest` (10 call sites), the inlined manifest encode-and-write block in
`install()` (5 sites), and `resolvedHooksBinaryURL` (5 sites). Extracted them into a
generic `ConfigManifestStore` enum — `load<M: Decodable>`, `write<M: Encodable>`,
`resolvedBinaryURL` — reproducing the persistence semantics exactly (`.iso8601`
decode/encode, `[.prettyPrinted, .sortedKeys]`, `.atomic` write, nil-for-missing but
throw-for-corrupt). Each manager's private `loadManifest`/`resolvedHooksBinaryURL`
became one-line delegates (signatures unchanged → ~15 call sites untouched); each
`install()` writes via `ConfigManifestStore.write`.

**Deliberately left per-manager** (recorded as decisions in the brief, not
oversights): `resolvedManifestURL` (Claude/Codex-only legacy fallback — sharing it
for 2 callers needs a 2-name param, not worth it), `backupFile` (a 1-line
`ConfigBackup` delegate — re-extracting is pure indirection), and all
install/uninstall/status orchestration (blast-radius isolation). No base class, no
protocol — that approach was rejected at scoping as too divergent/risky.

## Verification

- New `ConfigManifestStoreTests` (5): write→load round-trip asserting the on-disk
  sorted-keys + iso8601 form (A1), nil-for-missing + throws-for-corrupt (A2),
  resolvedBinaryURL explicit/executable/non-executable/nil (A3).
- TDD trail: `red:` (4af93f3) stubbed the helper nil/no-op → A1/A3 + the corrupt-load
  case failed on assertion (missing-file case benignly passed against the stub since
  nil is correct); Green (dc4452c) implemented + delegated; `git diff red..green --
  Tests/` = 0 bytes.
- Independent Verify (fresh context) PASS, no findings — reviewer inspected the red
  tree, byte-diffed the shared helper against the original inlined bodies across all
  5 managers (confirmed the premise: originals were byte-identical), confirmed all 5
  delegate correctly with unchanged private signatures, `resolvedManifestURL`
  preserved in Claude+Codex, `backupFile` + orchestration + OpenCode/ClaudeStatusLine
  untouched. Gate green: `harness.sh ci` (481 tests), exit 0.
- Behavior-neutrality proof: the `manager-roundtrip-tests` net (#44, Gemini/Kimi/
  Codex) + existing Claude/Cursor manager round-trip suites all pass unchanged —
  exactly the safety net slice C was landed to provide.

## Learning

- **The C+A sequencing paid off precisely as intended.** Slice C added manager-level
  round-trip coverage for Gemini/Kimi/Codex (previously zero/thin); this slice then
  relocated the config-manifest lifecycle for all 5 managers with that net catching
  any behavior drift. Extracting the helper first (without the net) would have
  rewritten the least-tested config-delete code with only pure-installer coverage —
  which never exercises the manager's read→write→manifest→status path. Land the net,
  then the refactor.
- **Generics are the right seam when copies differ only by a type parameter** (here
  the `Manifest` type), just as a closure was the right seam when copies differed by
  a decision (`HookGroupSanitizer`). `load<M: Decodable>` / `write<M: Encodable>`
  collapse 10+5 sites with zero behavior change because every manifest is `Codable`
  and the encode/decode strategies were already identical. The copy-paste hazard to
  guard at Verify is a strategy drift (a decoder losing `.iso8601`, an encoder
  dropping `.sortedKeys`, a write losing `.atomic`) — byte-diff the extracted body
  against an original, don't just eyeball the call sites.
- **Not everything that looks duplicated is worth extracting.** `backupFile` (1-line
  delegate) and `resolvedManifestURL` (2 callers, needs a 2-name param) were left
  alone on purpose — extracting them trades real duplication removal for indirection
  or a wider signature. Record these as explicit non-goals in the brief so Verify
  doesn't flag them as missed and a later reader doesn't "finish the job" wrongly.
- **Cluster B is now complete.** All safe mechanical dedups are done: serialize,
  loadRootObject, hook markers, group-hook walkers (`HookGroupSanitizer`), and now
  the manifest lifecycle (`ConfigManifestStore`). The manager base-class was
  deliberately NOT done (divergence is load-bearing). What remains in the audit is
  outside cluster B: cluster C mirrored events (#10) and the god-objects (#3
  BridgeServer, #8 AppModel).
