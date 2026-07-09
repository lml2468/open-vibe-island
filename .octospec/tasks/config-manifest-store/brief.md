---
type: Task
title: "Task: config-manifest-store"
description: Extract the byte-identical manifest load/encode-write + hooks-binary-URL resolution helpers shared across the 5 hook installation managers into a shared generic ConfigManifestStore; keep per-manager orchestration and the Claude/Codex-only legacy resolvedManifestURL in place
tags: ["dedup", "installer", "config", "correctness"]
timestamp: 2026-07-09T12:25:00Z
# --- octospec extension fields ---
slug: config-manifest-store
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — manager tier, extraction slice A)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T12:13:09Z
---

# Task: config-manifest-store

> Slice A of the C+A plan. The safe manager-tier dedup, landing on the round-trip
> test net merged in #44. A full manager base-class was **deliberately rejected**
> (too divergent/risky over the config-delete surface); this extracts ONLY the
> byte-identical helpers. Independent branch off `origin/main`. See
> `.octospec/tasks/config-manifest-store/discovery.md`.

## Goal

The 5 hook installation managers (Claude/Codex/Cursor/Gemini/Kimi) each carry three
duplicated pieces that differ ONLY by the per-manager `Manifest` type:
1. `loadManifest(at:) throws -> M?` — identical in all 5 (10 call sites).
2. The manifest **encode-and-write** block — inlined in each `install()` (5 sites).
3. `resolvedHooksBinaryURL(explicitURL:) -> URL?` — byte-identical in all 5 (5 sites).

Extract these into a new `ConfigManifestStore` enum (OpenIslandCore) with generic
static funcs:
```
static func load<M: Decodable>(at url: URL, fileManager: FileManager) throws -> M?
static func write<M: Encodable>(_ manifest: M, to url: URL) throws
static func resolvedBinaryURL(managedBinaryURL: URL, explicitURL: URL?, fileManager: FileManager) -> URL?
```
Each manager's `loadManifest`/`resolvedHooksBinaryURL` become one-line delegates
(preserving their existing private signatures so call sites are untouched), and each
`install()`'s inlined encode-write block becomes a `ConfigManifestStore.write(...)`
call. **Byte-equivalent relocation** — the decoder/encoder strategies and atomic
write are reproduced exactly. Same pattern as `HookGroupSanitizer`/`JSONConfigSerialization`.

## Deliberately NOT in scope (preserve divergence / avoid indirection)

- **`resolvedManifestURL()`** (Claude/Codex only — primary-vs-legacy fallback): left
  per-manager. Cursor/Gemini/Kimi have no legacy manifest; sharing it would add a
  two-name parameter for a 2-caller helper. Not worth it.
- **`backupFile(at:)`**: a 1-line delegate to `ConfigBackup`; re-extracting a
  1-liner is pure indirection. Left as-is.
- **All install/uninstall/status orchestration**: the read → mutate → backup →
  write → status skeleton stays per-manager — the explicit blast-radius-isolation
  decision from the C+A scoping. No base class, no protocol.

## Background

- **Injected rule:** `installer-config-safety` (load-bearing). The manifest lifecycle
  records the managed command that uninstall keys off; the binary resolution seeds
  the managed command. A byte-inequivalent extraction (wrong decoder strategy,
  non-atomic write, changed output formatting) would be a config-safety regression —
  so the shared funcs must reproduce `.iso8601` decode, `.iso8601` +
  `[.prettyPrinted, .sortedKeys]` encode, and `.atomic` write EXACTLY.
- Regression net: `HookInstallationManagerRoundTripTests` (#44) covers Gemini/Kimi/
  Codex full round-trips; Claude/Cursor have their own manager round-trip tests — so
  all 5 managers' install→uninstall→status paths are exercised through the real FS.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **New `ConfigManifestStore`** — the shared generic helpers; `write`/`load` must be
  encode/decode-symmetric and byte-equivalent to the inlined blocks. `[config]`
- **The 5 managers' `loadManifest` + `resolvedHooksBinaryURL`** — become one-line
  delegates; private signatures unchanged so their ~15 call sites are untouched.
  `[installer] [config]`
- **The 5 managers' `install()` manifest-write block** — replaced by a
  `ConfigManifestStore.write(...)` call. `[installer] [config]`
- **The install/uninstall/status flows** — unchanged behavior (manifest read/write,
  binary resolution, and everything downstream). `[installer] [config]`

## Out of scope
- `resolvedManifestURL`, `backupFile`, and all per-manager orchestration (above).
- Any manager base class / protocol / associated-type abstraction (rejected).
- OpenCode & ClaudeStatusLine managers (not part of the hook-manager cluster; they
  don't share this exact helper shape).
- No behavior change beyond the byte-equivalent helper relocation.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — `ConfigManifestStore.write` then `load` round-trips a Codable.** Writing a
  sample manifest to a temp URL via `write` then reading it via `load` returns an
  equal value; the written bytes are pretty-printed + sorted-keys + iso8601 dates
  (assert the on-disk JSON contains sorted keys / ISO date form). *(Testable: direct
  unit test. Fails first — the helper does not exist.)*
- **A2 — `load` returns nil for a missing file and throws for corrupt data.**
  `load` at a non-existent path returns `nil` (never throws for absence);
  `load` over non-decodable bytes throws. *(Testable: direct unit test. Fails first.)*
- **A3 — `resolvedBinaryURL` matches the current resolution.** Returns the
  standardized `explicitURL` when given; else the `managedBinaryURL` iff it is an
  executable file, else `nil`. *(Testable: direct unit test with a temp 0o755 file.
  Fails first.)*
- **A4 — managers delegate; behavior preserved.** After the swap, each of the 5
  managers' `loadManifest`/`resolvedHooksBinaryURL` bodies are one-line delegates to
  `ConfigManifestStore`, and each `install()` writes its manifest via
  `ConfigManifestStore.write`. The existing manager round-trip suites
  (`HookInstallationManagerRoundTripTests` for Gemini/Kimi/Codex + the Claude/Cursor
  manager round-trip tests) pass unchanged, including the Codex feature-flag toggle
  and manifest-hookCommand assertions. *(Testable: the #44 net + existing suites are
  the behavior-neutral proof; A1–A3 are the new positive tests for the helper.)*
- **A5 — gate green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`) with the new helper + delegates.
  *(N/A(test): the gate + existing manager suites are the behavior-neutral proof for
  the relocation; A1–A3 are the new unit tests.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
