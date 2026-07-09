---
type: Note
title: "Discovery: config-manifest-store"
description: Extract the byte-identical manifest load/encode-write + hooks-binary-URL resolution private helpers shared across the 5 hook installation managers into a shared ConfigManifestStore; leave per-manager orchestration and the Claude/Codex-only legacy resolvedManifestURL in place
tags: ["discovery"]
timestamp: 2026-07-09T12:20:00Z
# --- octospec extension fields ---
slug: config-manifest-store
upstream: arch-quality-audit-r2 (discovery finding #9, cluster B — manager tier, extraction slice A)
source: self
---

# Discovery: config-manifest-store

> The **Discover** phase output. Read-only exploration BEFORE the brief. This is
> slice A of the C+A plan — the safe manager-tier dedup, landing on top of the
> round-trip test net merged in #44. A full manager base-class was deliberately
> rejected (too divergent/risky); this extracts ONLY the byte-identical helpers.

## Relevant files
- The 5 hook installation managers (`Sources/OpenIslandCore/`):
  `ClaudeHookInstallationManager.swift`, `CodexHookInstallationManager.swift`,
  `CursorHookInstallationManager.swift`, `GeminiHookInstallationManager.swift`,
  `KimiHookInstallationManager.swift`.
- Existing shared helpers (precedent + collaborators): `ConfigBackup` (bounded
  backup), `HookGroupSanitizer`, `JSONConfigSerialization`, `OpenIslandHookMarkers`.
- Test net (merged #44): `HookInstallationManagerRoundTripTests` — full
  install→uninstall round-trip + status for Gemini/Kimi/Codex; Claude/Cursor have
  their own manager round-trip tests. This is the regression net for this slice.

## Existing behavior — the duplicated helpers (verified byte-identical)
Three pieces recur across all 5 managers, differing ONLY by the per-manager
`Manifest` type:

1. **`loadManifest(at:) throws -> M?`** — identical in all 5 (10 call sites):
   ```
   guard fileManager.fileExists(atPath: url.path) else { return nil }
   let data = try Data(contentsOf: url)
   let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
   return try decoder.decode(M.self, from: data)
   ```
2. **The manifest encode-and-write block** — inlined (not even a named func) in each
   `install()` (5 sites):
   ```
   let encoder = JSONEncoder()
   encoder.dateEncodingStrategy = .iso8601
   encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
   try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
   ```
3. **`resolvedHooksBinaryURL(explicitURL:) -> URL?`** — byte-identical in all 5
   (5 call sites):
   ```
   if let explicitURL { return explicitURL.standardizedFileURL }
   guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else { return nil }
   return managedHooksBinaryURL
   ```

## Contracts & blast radius
- These are pure mechanical helpers around the config-manifest lifecycle. The
  extraction is a byte-equivalent relocation with the leaf (Manifest type)
  parameterized via generics — same pattern the `installer-config-safety` rule
  already blessed for `HookGroupSanitizer`.
- **These helpers touch the config-delete/write surface indirectly** (they
  read/write the manifest that records the managed command, and resolve the binary
  that seeds the managed command). The manifest lifecycle drives what uninstall
  treats as managed — so an extraction bug (wrong decoder strategy, non-atomic
  write, wrong output formatting) is a config-safety regression. The #44 net +
  existing Claude/Cursor manager tests cover all 5 managers' round-trips.
- The manifest write is currently **inlined in `install()`**, so extracting it
  means each manager's install gains a one-line call — a visible, auditable change.

## Divergence to PRESERVE (do NOT fold in)
- **`resolvedManifestURL()`** — exists ONLY in Claude and Codex (primary-vs-legacy
  fallback: `fileName` → `legacyFileName`). Cursor/Gemini/Kimi have no legacy
  manifest. Leave it per-manager (or optionally share as a separate helper taking
  both names — but that's scope creep; default: leave it).
- **`backupFile(at:)`** — a 1-line delegate to `ConfigBackup.backup(_:fileManager:)`.
  Re-extracting a 1-liner adds indirection for no dedup value; leave it (or have
  managers call `ConfigBackup` directly — also scope creep; default: leave it).
- **All install/uninstall/status orchestration** — the read → mutate → backup →
  write → status skeleton stays per-manager (blast-radius isolation, the explicit
  decision from the C+A scoping).

## Risks & unknowns
- **Generics + `@unchecked Sendable` managers**: the shared helper should be a free
  enum with static generic funcs `load<M: Decodable>(at:fileManager:) throws -> M?`
  and `write<M: Encodable>(_:to:) throws`, plus a non-generic
  `resolvedBinaryURL(managedBinaryURL:explicitURL:fileManager:) -> URL?`. No stored
  state, so no Sendable concern.
- **Manifest types are `Codable`** (confirmed: e.g. `ClaudeHookInstallerManifest:
  Equatable, Codable, Sendable`), so generic decode/encode works. Confirm each of
  the 5 manifest types conforms to `Codable` (all seen so far do).
- **Byte-equivalence is the whole game**: decoder `.iso8601`, encoder `.iso8601` +
  `[.prettyPrinted, .sortedKeys]`, write `.atomic`. The shared funcs must reproduce
  these EXACTLY or a manifest round-trips differently (Verify must byte-diff).
- **Testable seam**: the shared helper takes `fileManager` as a param (managers
  already inject it), so no new seam. A direct unit test can round-trip a sample
  Codable through `write` then `load` in a temp dir and assert equality + that
  `load` returns nil for a missing file and throws for corrupt data.
- No human decision needed — the scope call (helpers yes, orchestration/
  resolvedManifestURL/backupFile no) is settled by the C+A plan; Plan just records
  it.
