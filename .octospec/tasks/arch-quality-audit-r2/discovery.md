---
type: Note
title: "Discovery: arch-quality-audit-r2"
description: Second full read-only architecture & code-quality assessment of Open Island on latest main, after the 7 remediation slices merged
tags: ["discovery", "audit", "architecture", "code-quality"]
timestamp: 2026-07-08T10:35:00Z
# --- octospec extension fields ---
slug: arch-quality-audit-r2
source: self
---

# Discovery: arch-quality-audit-r2

> **Read-only** re-assessment of the whole codebase on latest `main`
> (commit `4ea4c14`). This is the **second** full audit: a prior
> `arch-quality-audit` (commit `b585507`) found 33 issues and spawned **7
> merged remediation slices** (`#17`–`#23`: bridge-security, reducer-purity,
> installer-safety, quality-gates, perf-battery, dedup-registries,
> ui-decomposition). This pass (a) confirms what those slices genuinely fixed,
> (b) surfaces what they deliberately deferred, and (c) catches issues the
> earlier pass missed or that the refactors introduced. No code changed here.
>
> **Method:** 6 parallel read-only analysis passes (core state / god objects,
> systemic duplication, process-monitoring & perf, terminal-jump & AX,
> installers & network security, UI / build / CI / testing), each grounded in
> the prior findings so it reports *deltas* with current `file:line` evidence,
> plus direct verification of the highest-severity claims (`grep`/`Read`).
> **Scope:** ~39.4k LOC in `Sources/` (100 files), ~13.1k LOC in `Tests/`.

## Relevant files
<!-- Areas a remediation task would read or change, grouped by subsystem. -->

**Core state & event model**
- `Sources/OpenIslandCore/SessionState.swift` (485) — the "pure reducer": `apply(_:)` **+ 8 other public mutators**
- `Sources/OpenIslandCore/AgentEvent.swift` (386) — event enum + Codable hand-mirrored across 5 lists
- `Sources/OpenIslandCore/AgentSession.swift` (740) — session model (+ ~158-LOC Gemini de-dup; dead `isClaudeCodeFork`)
- `Sources/OpenIslandApp/AppModel.swift` (1,875) — `@Observable` god object (5 coordinators + ~70 LOC pass-through facade)

**Bridge / transport / IPC (largest single file)**
- `Sources/OpenIslandCore/BridgeServer.swift` (2,719) — one class: socket + framing + all 5 agents' business logic; `handleClaudeHook` alone is 406 LOC
- `Sources/OpenIslandCore/BridgeTransport.swift` (511) — codec + socket helpers (bridge fixes landed here)

**Network / Watch surface (highest remaining security exposure)**
- `Sources/OpenIslandCore/WatchHTTPEndpoint.swift` (651) — plain-HTTP-over-Bonjour; `WatchNotificationRelay.swift`

**Session discovery & process/transcript monitoring**
- `Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift` (1,458), `ActiveAgentProcessDiscovery.swift` (964), `SessionDiscoveryCoordinator.swift` (558)
- `Sources/OpenIslandCore/CodexSessionTracking.swift` (1,670), `TimedCache.swift`, `WorkspaceNameResolver.swift`

**Terminal jump & AX injection**
- `Sources/OpenIslandApp/TerminalJumpService.swift` (1,360), `TerminalJumpTargetResolver.swift` (848), `TerminalSessionAttachmentProbe.swift` (1,360)
- `Sources/OpenIslandApp/{OverlayPanelController,KeystrokeInjector}.swift`, `Sources/OpenIslandCore/WarpSQLiteReader.swift`

**Hook/plugin installers**
- `Sources/OpenIslandCore/*HookInstaller.swift` + `*HookInstallationManager.swift` (5 agents, no shared base)
- `Sources/OpenIslandApp/HookInstallationCoordinator.swift` (1,310 — untested, main-actor disk I/O)

**UI / presentation**
- `Sources/OpenIslandApp/Views/{AppearanceSettingsPane (1,583), SettingsView (1,302), IslandSessionRow (875)}.swift`
- `Sources/OpenIslandApp/Design/DesignTokens.swift` — defined, ~1% adopted

**Build / CI**
- `Package.swift` (no `swiftSettings`), `.swiftlint.yml` (23 parked rules), `scripts/harness.sh`, `.github/workflows/`

## Existing behavior
<!-- How the load-bearing paths work today, after the 7 slices. -->
- **Confirmed FIXED by the prior slices** (verified at current `file:line`):
  - *Bridge:* `writeAll` now has a 5s monotonic deadline (`BridgeTransport.swift:477-511`); peer uid enforced via `getpeereid` + default-deny (`:453-470`, `BridgeServer.swift:230-233`); both sockets `chmod 0600` (`BridgeServer.swift:145-147`); forward-compat decode skips unknown frames (`BridgeTransport.swift:365-374`); 4MB frame cap (`:342`).
  - *Reducer:* injectable clock on `dismissSession`/`resolvePermission`/`answerQuestion`; `answerQuestion` end-guard; `markProcessLiveness` stale-count reset.
  - *Installer:* OpenCode/Cursor throw-not-clobber on malformed config; `ConfigBackup` bounded retention (all 8 managers delegate); Cursor `version` preserved.
  - *Perf:* `CodexUsage` streams via chunked `FileHandle` (`:130-161`); fractional-second timestamps via shared `TranscriptTimestamp.parse` (`:20-35`); single shared `extractNDJSONLines` at all 4 sites (O(n²) front-removal gone).
  - *Dedup:* 4 session registries → `SessionRegistryStore`; `backupFile` → `ConfigBackup`.
  - *Quality gates:* warnings-as-errors + SwiftLint in CI; shipped PII removed from `Sources/` (0 hits); `HookFailOpenTests` exists.
- Data flow, poll cadence, and fail-open principle otherwise unchanged from the prior discovery. Monitoring wakes every 2s (Codex.app probe) and does a full reconcile every 60s (active) / 300s (idle); `CodexRolloutWatcher` uses a 3s `DispatchSourceTimer` on known files with incremental offset reads.

## Contracts & blast radius (→ becomes the brief's Load-bearing list)

Findings are grouped by severity. `[tag]` maps to prospective `inject_when.touches`.
Numbering is fresh for r2; where a finding continues a prior one, the old id is noted.

### HIGH

1. **[security] The Watch/iPhone bridge ships tokens and session content in cleartext** — the single most serious *remaining* issue, and it undercuts the same-user hardening done on the Unix socket. `WatchHTTPEndpoint.startListener` uses `NWParameters.tcp` with **no `.tls`** (`WatchHTTPEndpoint.swift:220`). Bearer tokens (`:617-621`), the `/pair` token exchange (`:474-478`), and SSE payloads carrying `summary` / `title` / `workingDirectory` / prompt & question text (`:33-56`) all traverse the LAN unencrypted; any same-network host can sniff a bearer token and replay it to `/resolution` to approve or deny an agent's tool use. (Prior #29, still open, promoted to HIGH now that it is the top exposure.)

2. **[perf/battery] Poll-everything discovery with per-agent subprocess fan-out** — the dominant CPU/battery cost of an always-on app. No FSEvents/DispatchSource on `~/.claude/projects` or `~/.codex/sessions` (verified: no `FSEventStream`/`kqueue` anywhere); discovery is timer-driven directory enumeration. `ActiveAgentProcessDiscovery.discover()` spawns, serially per sweep, `1 ps + P lsof + 2T tmux [+ T which]` (`ActiveAgentProcessDiscovery.swift:220,253,287,341,858-956`), and `resolveTmuxInfo` is **not memoized across agents** in a sweep (each tmux-attached agent re-runs `list-panes -a` + `list-clients`). Runs off-main and timeout-bounded, but is periodic fork/exec drain. (Prior #15, partially addressed — the O(n²)/formatter parts are fixed; the subprocess-fanout + no-FSEvents parts remain.)

3. **[architecture] `BridgeServer.swift` (2,719 LOC) is one class doing socket + framing + all 5 agents' logic, with no strategy seam** — the biggest file in the repo. Single `final class`, no `AgentHookHandler`/strategy protocol (verified: none). Socket accept/framing is entangled with per-agent business logic; `handleClaudeHook` is a **406-line** method (`:646-1052`), and each agent carries its own ensure/synchronize/merge helper cluster. Adding an agent means editing the giant `handle` switch (`:334`, 171 lines) + a new ~150-line handler inline. (Prior #5 — the `IslandPanelView` third of it was split; this and `AppModel` remain.)

4. **[testability] The two largest orchestration files have zero dedicated tests** — `HookInstallationCoordinator.swift` (1,310, mutates user configs — the very subsystem installer-safety just hardened) and `ProcessMonitoringCoordinator.swift` (1,458) have **no** test suite (only an incidental comment reference in `ClaudeUsageTests.swift:364`). `SessionDiscoveryCoordinator` (558) and `HarnessArtifactRecorder` (650) likewise. Reversibility/liveness are asserted by inspection only. (Prior #8, still open.)

5. **[correctness] The jump path violates fail-open and can hang uncancellably** — two joined problems on the app's headline feature. (a) AppleScript jumps use `try` and **throw** on Automation denial, unwinding `jump(to:)` past the `open -b` fallbacks (`TerminalJumpService.swift:351,359,363,268`) — a user who declined the Automation prompt gets a hard error instead of plain app activation. (b) Every subprocess runner uses `waitUntilExit()` with **no timeout** (`:1285,1303,1327,677,757,1125`, + `WarpSQLiteReader.swift:363` pgrep; 11 `waitUntilExit` in the jump file), and `Task.cancel()` can't interrupt a blocking wait — a hung `osascript`/`code`/`idea` leaks a Process + task per attempt. (Prior #18, still open.)

6. **[maintainability] Design-token system is effectively dead (~1% adoption)** — `DesignTokens.swift` defines 6 ladders, but app-wide usage is `IslandOpacity`×4, `IslandRadius`×1, and `IslandSpacing`/`IslandTypography`/`IslandMotion`/`IslandShadow` **×0**, against **234** `.opacity(`, **111** `.system(size:`, **49** `cornerRadius:` raw literals in `Views/` alone. `DesignTokensTests` validates the ladders but nothing consuming them, giving false coverage confidence. The `ui-decomposition` split spread these literals across more files, so a token-migration slice now touches more sites. (Prior #17, unchanged/worse.)

### MEDIUM

7. **[architecture] `apply(_:)` is still not the single source of truth CLAUDE.md claims.** 8 public mutators bypass it (`SessionState.swift:237,284,313,331,365,376,463,474`), and the "don't resurrect an ended session" invariant is hand-copied in **≥4 shapes** (`apply:99`, `resolvePermission:253-257`, `answerQuestion:303-307` whose own comment says "Mirror resolvePermission", `markProcessLiveness:410`). The fold-into-`apply` refactor is still pending. (Prior #1; reducer-purity fixed the guards' *behavior* but not the *duplication*.) Captured rule `session-state-invariants` predicts this.

8. **[architecture] `AppModel.swift` (1,875) remains a god object.** 5 coordinators are composed in, but it keeps ~10 responsibilities plus a large pure-delegation surface: ~50 one-line `hooks.*` pass-throughs (`:96-208`), ~20 `overlay.*` pass-throughs (`:1237-1256`), misplaced hex-color extensions (`:1849-1874`), and `watchConnectedDevices` still a hardcoded `0` stub (`:465-468`). (Prior #5/#33.)

9. **[maintainability] Systemic per-agent duplication — the dominant code-quality theme — is largely still open.** Registries and `backupFile` are done; what remains:
   - **Terminal AppleScript probing cluster (~200-300 LOC)** — Ghostty/Terminal.app scripts + `runAppleScript` + `GhosttyTerminalSnapshot`/`TerminalTabSnapshot` structs + `isRunning`/`normalizedTerminalName` + `corrected*JumpTarget` are byte-/near-identical between `TerminalJumpTargetResolver.swift` and `TerminalSessionAttachmentProbe.swift` (`:682-843` vs `:1171-1355`). Biggest remaining copy-paste surface.
   - **Hook installers/managers (~250-400 LOC)** — no shared base/protocol; `loadRootObject`, `serialize` (`[.prettyPrinted,.sortedKeys]` one-liner), `sanitize`/`containsManagedHook`, and 5 `isOpenIsland*HookCommand` predicates are parallel copies across Claude/Codex/Cursor/Gemini/Kimi; the manager `status/install/uninstall` skeletons are line-for-line parallel.
   - **Per-agent metadata plumbing (~120-160 LOC)** — 5 mirrored `*SessionMetadataUpdated` events (enum + `CodingKeys` + `EventType` + `init(from:)` + `encode` arms) in `AgentEvent.swift`, 5 `*SessionMetadata.isEmpty`, and 2 layers of `merge*Metadata` (`SessionDiscoveryCoordinator.swift:245-333` + `BridgeServer.swift:1694-2398`).
   - **`shellQuote` ×5** (`*HookInstaller.swift`), **`escapeAppleScript` ×2**. (Prior #6.)

10. **[maintainability] `AgentEvent` Codable is hand-mirrored across 5 parallel lists** (cases/`CodingKeys`/`EventType`/`init(from:)`/`encode`, `AgentEvent.swift:242-375`). bridge-security added the forward-compat *guard* (`:289-294`) but did not reduce the mirroring — adding one event still means editing all 5 sites. Also, both `AppModel.applyTrackedEvent:1541-1556` and `ProcessMonitoringCoordinator.sessionID(for:):357-384` re-enumerate all 12 cases just to extract `sessionID`, which every payload already has — should be one computed `var sessionID` on the enum. (Prior #10/#32.)

11. **[correctness] Codex rollout tailing assumes append-only** — `CodexRolloutWatcher.refresh` resets offset only when `fileSize < offset` (`CodexSessionTracking.swift:1488-1502`); an in-place compaction/rewrite to ≥ the old size seeks to a stale offset and feeds mid-record bytes into the reducer (silently dropped as parse failures → stuck/incorrect snapshot). (Prior #16, still open.)

12. **[correctness/i18n] Codex turn-termination via localized substring match** — `isTerminalFailureMessage` matches `"你已达到使用上限"`/`"usage limit"`/`"rate limit"` etc. (`CodexSessionTracking.swift:1085-1104`): brittle for non-EN/ZH users and false-positives when the assistant discusses those phrases. A structured `applyRateLimitSignal` path exists (`:831-859`); the substring heuristic is a fallback that should be narrowed. (Prior #28.)

13. **[perf] Installer `status()` disk I/O runs on `@MainActor`** — `HookInstallationCoordinator` is `@MainActor`; its refreshers `Task { @MainActor … }` call synchronous disk-reading `manager.status()` on the main actor (`:562-566,575-579,599-603,614-691,696-738`), and `refreshAllHookStatusAndWait` does this for ~10 agents on launch and after every install. The usage loaders correctly use `Task.detached(.utility)` — the fix pattern is known but applied inconsistently. (Prior #23.)

14. **[correctness] AX/HID injection assumes permission — no `AXIsProcessTrusted()` anywhere** (verified: 0 hits in `Sources/`). `KeystrokeInjector.sendCmdShiftRightBracket` drives Warp's menu via AppleScript with no permission gate; on denial it `NSLog`s and returns, and the caller then wastes its full `tabCount+2` cycle loop (each iteration a real `Thread.sleep(0.1)` + SQLite read). Also a **hardcoded English menu path** (`"Switch to Next Tab"`, `:65`) that silently fails on localized systems, and `OverlayPanelController.repostMouseDown` posts `CGEvent`s to `.cghidEventTap` with no capability check. (Prior #31, expanded.)

15. **[perf] Overlay global `NSEvent` monitors are retained for the process lifetime** — `NotchEventMonitors.start` installs 4 global/local monitors (`OverlayPanelController.swift:804-826`); a correct `stop()` exists (`:833-842`) but is **never called** (verified) and `hide()` doesn't quiet them, so the app taps every system-wide mouse-move/click even while the island is closed. Plus `nonisolated(unsafe) sharedLastMove` (`:802`) is mutated unsynchronized from two monitor closures (`:806,814`). (Prior #24.)

16. **[correctness] AppModel↔coordinator wiring swallows nil into an empty world** — `stateAccessor?() ?? SessionState()` in both `ProcessMonitoringCoordinator.swift:100` and `SessionDiscoveryCoordinator.swift:76`: a wiring miss / lifecycle race silently substitutes a fresh empty `SessionState` instead of failing or logging, so a mis-wired coordinator appears to work against nothing. (Prior #27, still open.)

17. **[build/ci] Quality gates exist but sit above deferred debt.** (a) `Package.swift` has **no `swiftSettings`** — warnings-as-errors lives only in `scripts/harness.sh:24,33`, so a plain `swift build`/Xcode build isn't gated, and strict-concurrency is not enabled at the manifest despite **26 `@unchecked Sendable`** (verified). (b) `.swiftlint.yml` parks **23 rules**, including god-object maskers (`file_length`/`type_body_length`/`function_body_length`/`cyclomatic_complexity`/`nesting`) that hide findings #3/#4b, and correctness rules (`force_cast`/`force_try`) disabled *globally* (they lint `Sources` too, not just `Tests`). (c) **159 `try?`** error-swallows with no logging and no gate. (Prior #26 — enforcement landed, but with carve-outs worth tracking down.)

### LOW / NEW

18. **[architecture] No per-terminal `TerminalJumper` strategy** — jump dispatch is 3 separate `switch`es on bundle id (`TerminalJumpService.swift:335,261,993`) + `knownApps` + per-terminal `jumpToX` methods across 3 files. A protocol would collapse the switches and let #9's AppleScript cluster move per-terminal. (Prior #25.)

19. **[dead code] `AgentTool.isClaudeCodeFork` is defined but never called** (`AgentSession.swift:65-72`, verified 0 usages) while the same fork list is hand-inlined in `SessionState.swift:262,272`; `isTrackedLiveSession` also hand-lists tracked tools as a 10-way `||` (`:511`) that will silently miss any newly added tool. **NEW** (a purpose-built helper left stranded by reducer-purity).

20. **[security] 4-digit Watch pairing code** (`pairingCodeLength = 4` → 10,000 combos, `WatchHTTPEndpoint.swift:116`); throttle allows ~7,200 guesses/hr, exhaustible in <1 day, and combined with #1's cleartext the code needn't even be guessed. Token compare is non-constant-time (`validTokens.contains`, `:621`). **NEW/expanded.**

21. **[correctness] Multi-file installs aren't transactional** — Codex writes `config.toml` then `hooks.json` then manifest separately (`CodexHookInstallationManager.swift:110-122`); a crash between leaves `[features] hooks=true` with no `hooks.json`. No rollback wrapper. (Prior #21, still open.)

22. **[maintainability] Hand-rolled TOML editing still mis-handles non-canonical `[features]`** — `CodexHookInstaller.enableCodexHooksFeature` (`:162-222`, `sectionRange:415-430`) doesn't recognize inline (`features = { hooks = true }`) or dotted (`features.hooks = true`) forms and will **append a duplicate `[features]` table** (TOML-invalid) in those cases. (Prior #22.)

23. **[perf] Minor unbounded/main-actor items:** `TimedCache` has no size cap and never purges expired entries (`TimedCache.swift`, only `gitBranchCache`, low cardinality, slow leak); `SessionDiscoveryCoordinator.reconcileStalledCodexAppSessionsIfNeeded` does a synchronous `~/.codex/archived_sessions` dir scan on the **main actor** every ~15s while Codex.app runs (`:398-411`, called twice per refresh); JSON installers reformat whole files with `.prettyPrinted,.sortedKeys`, causing a spurious "changed"→backup + key-reorder on first install. (Prior #33 + NEW.)

24. **[maintainability] View files still oversized:** `AppearanceSettingsPane.swift` (1,583 — now the largest view; ~700 LOC of relocatable private previews `:851-1560`), `IslandSessionRow.swift` (875 — a single `View` body needing real decomposition, explicitly deferred by the split), `SettingsView.swift` (1,302 — 13 top-level panes, mechanically splittable). The `ui-decomposition` split also widened ~35 view helper types from `private` to `internal` with no submodule boundary. (Prior #5, next candidates.)

25. **[security] cmux socket path & CLI PATH resolution trust untrusted input** — `resolveCmuxSocketPath` reads the target from world-writable `/tmp/cmux-last-socket-path` (`TerminalJumpService.swift:582,596`; mitigated: bounds-checked, payload JSON-escaped); editor CLIs run via `/usr/bin/env` against inherited `PATH` and `which` fallbacks (`:1320,701,779,1014`) — a planted `code`/`idea` on an attacker-controlled PATH entry would execute. (Prior #30.)

**Positives (hold up well):** all four bridge hardening fixes verified in place; frame cap bounds `decodeLines`; `CodexUsage` streaming + shared line extractor + fractional timestamps verified; `ConfigBackup`/`SessionRegistryStore` dedup clean; PII gone from `Sources/`; monitors in `ProcessMonitoringCoordinator`/`CodexRolloutWatcher` are correctly cancelled (no leak); the `ui-decomposition` split left no dead code; pairing has throttle + expiry + size cap; startup discovery is off-main; still 0 TODO/FIXME, 2 `fatalError`, 2 `as!`.

## Risks & unknowns (resolve at / before Plan)

- **Scope is again far too large for one brief/PR** — same slicing discipline as r1 applies (see the `octospec-large-audit-slicing` memory). Recommended cut, highest ROI first, each its own `/octospec` cycle:
  1. **Watch/network security** — #1 (TLS or explicit accept-the-risk decision), #20 (pairing entropy + constant-time compare). Small, high-impact, and the top remaining exposure.
  2. **Jump fail-open + subprocess timeouts** — #5 (fallback on Automation denial + bounded `waitUntilExit`), #14 (`AXIsProcessTrusted` gate). Contained to the jump/AX files; directly user-visible.
  3. **Reducer single-source-of-truth** — #7 fold mutators into `apply`, dedupe the resurrection guard, + #19 use `isClaudeCodeFork`. Backed by the existing `SessionStateTests`.
  4. **Coordinator test coverage** — #4 (Hook/Process coordinators) + #16 (nil-swallow → explicit failure). Enables safe future refactors of the god objects.
  5. **Perf/battery** — #2 (FSEvents + memoized tmux), #11 (rollout compaction), #13 & #23 (main-actor I/O). Battery is the core cost of an always-on app.
  6. **De-duplication refactors** — #9 (AppleScript cluster, installer base, metadata plumbing) + #10 (`AgentEvent` `sessionID` property). Large, mechanical, lower-risk once tests exist.
  7. **God-object decomposition** — #3 (`BridgeServer` per-agent handlers), #8 (`AppModel` facade extraction), #18 (`TerminalJumper` protocol), #24 (view splits), then re-enable the parked lint rules (#17b).
  8. **Design tokens** — #6 migrate literals → tokens (or delete the dead ladders and be honest about it).
- **Decision needed (carried from r1, now sharper):** is the network threat model in scope? #1 is genuinely serious for a "local-first" app that nonetheless opens an unauthenticated-transport LAN surface. The maintainer must explicitly either add TLS/pinning or document "same-LAN trust accepted" — it should not stay an accident.
- **Decision needed:** are the 26 `@unchecked Sendable` + strict-concurrency-off (#17) deliberate pragmatism or debt? This bounds how hard the quality-gate slice should push toward Swift 6 language mode.
- **Verification gaps:** #11 (in-place compaction) and #14 (localized menu path failure) were reasoned from code, not reproduced at runtime — each remediation brief should add a failing test / manual repro first, per the octospec Red step.
- **Note:** the prior `arch-quality-audit` slug is fully consumed (7 merged slices). This r2 discovery intentionally lives under a new slug so its brief and journal don't collide with the finished r1 artifacts.
