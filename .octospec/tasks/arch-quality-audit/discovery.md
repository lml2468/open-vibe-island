---
type: Note
title: "Discovery: arch-quality-audit"
description: Full read-only architecture & code-quality assessment of Open Island on latest main
tags: ["discovery", "audit", "architecture", "code-quality"]
timestamp: 2026-07-07T12:12:39Z
# --- octospec extension fields ---
slug: arch-quality-audit
source: self
---

# Discovery: arch-quality-audit

> **Read-only** assessment of the whole codebase on latest `main` (commit `b585507`).
> Goal of the eventual task: identify, prioritize, and (later) address architecture
> and code-quality problems. No code changed in this phase.
>
> Method: 7 parallel read-only analysis passes over the four targets, plus direct
> reading of the load-bearing files (`SessionState.swift`, `Package.swift`) and
> targeted verification of the highest-severity claims (`grep`/`Read`). Findings
> below are evidence-backed with `file:line`. Scope: 92 source files, ~39,071 LOC in
> `Sources/`, ~12,288 LOC / 345 `@Test` cases in `Tests/`.

## Relevant files
<!-- Areas a remediation task would read or change, grouped by subsystem. -->

**Core state & event model**
- `Sources/OpenIslandCore/SessionState.swift` — the "pure reducer" (`apply(_:)` + ~9 other mutators)
- `Sources/OpenIslandCore/AgentEvent.swift` — event enum + hand-rolled Codable
- `Sources/OpenIslandCore/AgentSession.swift` — session model (+ ~160 LOC Gemini de-dup logic)
- `Sources/OpenIslandApp/AppModel.swift` — 1,875-LOC `@Observable` god object
- `Sources/OpenIslandCore/AgentIntentStore.swift`, `AgentHookIntent.swift`

**Bridge / transport / IPC**
- `Sources/OpenIslandCore/BridgeServer.swift` — 2,701-LOC god object (socket + framing + all agent business logic)
- `Sources/OpenIslandCore/BridgeTransport.swift` — codec, socket helpers, `writeAll`
- `Sources/OpenIslandCore/{LocalBridgeClient,BridgeCommandClient}.swift`
- `Sources/OpenIslandHooks/OpenIslandHooksCLI.swift` — fail-open hook CLI
- `Sources/OpenIslandCore/{WatchHTTPEndpoint,WatchNotificationRelay,HookHealthCheck}.swift`

**Session discovery & process/transcript monitoring**
- `Sources/OpenIslandCore/CodexSessionTracking.swift` (1,711), `CodexUsage.swift`, `ClaudeUsage.swift`
- `Sources/OpenIslandApp/{ProcessMonitoringCoordinator,ActiveAgentProcessDiscovery,SessionDiscoveryCoordinator}.swift`
- `Sources/OpenIslandCore/{Claude,Cursor,OpenCode}SessionRegistry.swift`, `ClaudeTranscriptDiscovery.swift`, `CursorTranscriptReader.swift`
- `Sources/OpenIslandCore/{WarpSQLiteReader,WarpProcessResolver,TimedCache}.swift`

**Terminal jump & AX injection**
- `Sources/OpenIslandApp/{TerminalJumpService,TerminalJumpTargetResolver,TerminalSessionAttachmentProbe}.swift`
- `Sources/OpenIslandApp/{ForegroundTerminalSessionProbe,KeystrokeInjector,TerminalTextSender}.swift`

**Hook/plugin installers & setup**
- `Sources/OpenIslandCore/*HookInstaller.swift` + `*HookInstallationManager.swift` (Claude/Codex/Cursor/Gemini/Kimi)
- `Sources/OpenIslandCore/{OpenCodePluginInstallationManager,ClaudeStatusLineInstallationManager,HooksBinaryLocator}.swift`
- `Sources/OpenIslandApp/HookInstallationCoordinator.swift` (1,310), `Sources/OpenIslandSetup/OpenIslandSetupCLI.swift`

**UI / presentation**
- `Sources/OpenIslandApp/Views/{IslandPanelView,AppearanceSettingsPane,SettingsView}.swift` (2,779 / 1,583 / 1,302)
- `Sources/OpenIslandApp/{OverlayPanelController,OverlayUICoordinator,IslandSurface}.swift`
- `Sources/OpenIslandApp/Design/{DesignTokens,BrandPalette}.swift`, `IslandDesignPalette.swift`

**Build / CI**
- `Package.swift`, `.github/workflows/{ci.yml,design-lint.yml,release.yml}`, `scripts/harness.sh`

## Existing behavior
<!-- How the load-bearing paths work today. -->
- Data flow is as documented: `agent hook → OpenIslandHooks (stdin) → Unix socket → BridgeServer → AppModel → UI`, with a pure-reducer intent (`SessionState.apply`) and fail-open hooks.
- `SessionState` is a `struct` keyed by `sessionsByID`; it exposes `apply(_:)` **plus** `resolvePermission`, `answerQuestion`, `reconcileAttachmentStates`, `reconcileJumpTargets`, `markSingleSessionAlive`, `markProcessLiveness`, `dismissSession`, `removeInvisibleSessions`.
- Discovery/monitoring is **poll-based**: rollout watcher 3s, session rescan 10s, reconcile 15s, `ps`/`lsof` sweeps 60s/300s (2s during startup).
- Bridge is a single serial `bridge.server` queue; server writes use a `usleep(1_000)`-spin `writeAll` with **no timeout** (`BridgeTransport.swift:425`). Primary socket `~/.../…`, legacy socket `/tmp/open-island-<uid>.sock` (`BridgeTransport.swift:19`); no `chmod`/peercred (verified).
- The harness/debug scenarios are **env-var gated** (`OPEN_ISLAND_HARNESS_SCENARIO`, `HarnessLaunchConfiguration.swift:13`) — not shown in normal release UI — but `IslandDebugScenario.swift` is compiled into the app target unconditionally (no `#if DEBUG`).
- Testing is deep on the pure reducer (`SessionStateTests` 40 `@Test`), hook parsing, and bridge codec/merge; thin-to-absent on the large orchestration/UI files.

## Contracts & blast radius (→ becomes the brief's Load-bearing list)

Findings are grouped by severity. `[tag]` maps to prospective `inject_when.touches`.

### HIGH
1. **[architecture] `apply(_:)` is not the single source of truth it claims to be.** `SessionState.swift` has ~9 public mutators besides `apply`; CLAUDE.md + the file header assert `apply(_:)` is *the* mutation path. The invariant the whole design leans on is not enforced. `SessionState.swift:56,237,284,301,319,354,365,450,458`.
2. **[correctness/testability] The "pure reducer" reads wall-clock time.** `resolvePermission`/`answerQuestion` default `timestamp: Date = .now` (`:240,:287`) and `dismissSession` hardcodes `.now` (`:454`) — non-deterministic `updatedAt`/sort, not purely testable.
3. **[correctness] `writeAll` busy-spins with no timeout on a shared serial queue.** One stuck/slow/malicious reader whose buffer fills wedges the *entire* bridge — all clients, hook dispatch, state processing. Strongest head-of-line-blocking/DoS finding. `BridgeTransport.swift:425-446` + `BridgeServer.swift:2593,2606`.
4. **[security] No peer auth + world-visible legacy socket, no `chmod`.** Any local process can connect and send `resolvePermission`/`answerQuestion`/`process*Hook` — approve/deny an agent's tool use or spoof sessions. `BridgeServer.swift:114`, `BridgeTransport.swift:18-20` (verified: no `chmod`/`LOCAL_PEERCRED`/`getpeereid`).
5. **[architecture] Three 2000-2700-LOC god objects.** `BridgeServer.swift` (2,701 — socket + framing + all 5 agents' logic), `IslandPanelView.swift` (2,779 — 6+ components, `IslandSessionRow` alone 870 LOC), `AppModel.swift` (1,875 — ~10 responsibilities incl. free-function hex helpers at `:1849`).
6. **[architecture] Systemic per-agent duplication (the dominant code-quality theme).** Copy-paste across: the 4 session registries (`Claude/Cursor/OpenCode` + `CodexSessionStore` — identical `load`/`save`/atomic-write, ~500 LOC dedupe potential); 5-7 `*HookInstallationManager` classes; `backupFile(at:)` verbatim in **7** files; `shellQuote` in 5; `escapeAppleScript` in 3; the Ghostty/Terminal.app AppleScripts duplicated between `TerminalJumpTargetResolver.swift:677-774` and `TerminalSessionAttachmentProbe.swift:1170-1259`; 4 near-identical `merge*Metadata` fns; 5 mirrored per-tool metadata events. Adding one agent touches ~10 sites.
7. **[correctness/safety] OpenCode installer clobbers a malformed config.** `OpenCodePluginInstallationManager.registerPluginInConfig` (`:156-162`) resets `json = [:]` on a non-decodable `config.json` and writes back only its own block — destroying the user's config (backup taken, but silent/destructive). Every other installer throws instead.
8. **[testability] The config-mutating coordinator is untested.** `HookInstallationCoordinator.swift` (1,310) has no dedicated suite; reversibility is asserted by inspection only. Fail-open contract (`OpenIslandHooksCLI.swift:61-112`) has **0** tests simulating a dead bridge.
9. **[code-smell] Shipped developer PII paths.** `IslandDebugScenario.swift` embeds `/Users/wangruobing/Personal/...` in 9 string literals (`:237` et al.), compiled into the app target with no `#if DEBUG`. Env-gated from UI, but present in the shipped binary. (Downgraded from High → Medium after verifying the env gate.)

### MEDIUM
10. **[maintainability] `AgentEvent` Codable is hand-mirrored across 5 sites** (enum, `CodingKeys`, `EventType`, `init(from:)`, `encode`) with **no unknown-type fallback** — a newer hook's event type throws `DecodingError`, ending the bridge stream loop (`AppModel.swift:1203`) and forcing a full reconnect (forward-compat/fail-open hazard). `AgentEvent.swift:255-369`.
11. **[correctness] `answerQuestion` lacks the `isSessionEnded` guard** that `resolvePermission` has (`SessionState.swift:284-299` vs `:253-257`) — can resurrect an ended session into a running-but-invisible phantom.
12. **[correctness] `markProcessLiveness` drops a `processNotSeenCount` reset** when a session stays alive (`SessionState.swift:423-438`), leaving a stale count in the map; the 78-line multi-branch fn is the hardest-to-reason-about code in the reducer.
13. **[correctness] Claude transcript timestamps never parse** — default `ISO8601DateFormatter()` without `.withFractionalSeconds` vs Claude's fractional-second stamps (`ClaudeTranscriptDiscovery.swift:107`); always falls back to file mtime (recency/ordering/prune run off mtime). Codex does it right (`CodexSessionTracking.swift:1708`).
14. **[performance] `CodexUsageLoader` re-introduces the OOM pattern** — `String(contentsOf:)` slurps whole rollout JSONL files (`CodexUsage.swift:124`), the exact thing the streaming refactor removed elsewhere.
15. **[performance] Poll-everything + per-sweep subprocess fan-out.** No FSEvents/DispatchSource for known files; `ActiveAgentProcessDiscovery` spawns N sequential `lsof`/`tmux`/`which` per sweep (`:129,187,204,253,287,341,884-935`); O(n²) line extraction via `Data` front-removal (`CodexSessionTracking.swift:552`, `ClaudeTranscriptDiscovery.swift:221`); per-line `ISO8601DateFormatter`/`NSRegularExpression` allocation. Dominant CPU/battery cost of an always-on app.
16. **[correctness] Rollout tailing assumes append-only** — only resets on truncation (`CodexSessionTracking.swift:1500-1516`); an in-place compaction to ≥ size feeds mid-record garbage into the reducer.
17. **[maintainability] Design-token system is effectively dead.** `DesignTokens.swift` defines tokens, but views are saturated with raw literals (`.opacity(0.055)`, `cornerRadius: 10`, `size: 10.5`); tokens referenced only a handful of times. (Note: `design-tokens-sync` rule exists but governs `DESIGN.md`↔Swift, not literal usage.)
18. **[correctness] Jump path violates fail-open + can hang.** AppleScript jumps `throw` on Automation denial instead of falling back to `open -b` (`TerminalJumpService.swift:351-366`); `osascript`/`open` runners have **no timeout** (`:1280,:1293`) unlike the probes; `jumpToWarpPane` blocks the caller up to ~1.5s+ with `Thread.sleep` (`:1153-1211`).
19. **[correctness/UI] Cursor install clobbers user `version`; JSON installers reformat whole files.** `CursorHookInstaller.swift:57` overwrites top-level `version`; all JSON writers reserialize with `.prettyPrinted,.sortedKeys`, destroying user key order and triggering spurious "changed"→backup on first install.
20. **[safety] Backups created on every changed write, never pruned** (7 copies of `backupFile`), driven by auto-install/repair loops → unbounded `*.backup.<iso>` litter in `~/.claude`, `~/.codex`, `~/.cursor`.
21. **[correctness] Multi-file installs aren't transactional** — Codex writes `config.toml` then `hooks.json` separately (`CodexHookInstallationManager.swift:110-113`); a crash between leaves flag-on/hooks-missing.
22. **[maintainability] Hand-rolled TOML editing** (`CodexHookInstaller.enableCodexHooksFeature:162`) mis-handles non-canonical `[features]` layouts and can append a duplicate table TOML forbids.
23. **[maintainability/perf] Installer `status()` disk I/O runs on `@MainActor`** (`HookInstallationCoordinator` Tasks inherit main isolation, `:561,574,708…`) — blocks UI, inconsistent with the `Task.detached` usage loaders.
24. **[correctness] `OverlayPanelController` never removes its 4 global/local `NSEvent` monitors** (`start()` at `:227-239`, no `stop()` caller) — unbalanced resource, `hide()` doesn't quiet them; plus `nonisolated(unsafe)` unsynchronized `sharedLastMove` throttle (`:802-819`).
25. **[architecture] No per-terminal strategy abstraction** — jump dispatch is a giant `switch` on bundle id across two switches + `knownApps` + 3 files (`TerminalJumpService.swift:335-398`); no `TerminalJumper` protocol.
26. **[build/ci] No strict-concurrency gate + no Swift linter.** `Package.swift` sets no `swiftSettings`/strict-concurrency flags despite 26 `@unchecked Sendable` types; CI "lint" is only `lint-strings.sh` (`harness.sh:26`), no SwiftLint/SwiftFormat, so `try?`(×155)/force-unwrap/`@unchecked` drift is ungated.
27. **[architecture] AppModel↔coordinator wiring via optional callbacks that swallow nil.** `stateAccessor?() ?? SessionState()` treats a wiring miss as "no sessions," degrading silently (`ProcessMonitoringCoordinator.swift:99-102`, `SessionDiscoveryCoordinator.swift:75-81`).

### LOW (representative)
28. **[correctness] Codex turn-termination via localized substring match** ("usage limit"/"你已达到使用上限", `CodexSessionTracking.swift:1108-1127`) — brittle; should prefer the structured `rate_limits` signal.
29. **[security] Watch/iPhone endpoint is plain HTTP over Bonjour** — bearer tokens + prompts/cwd traverse the LAN in cleartext, replayable (`WatchHTTPEndpoint.swift:218-257`); token compares non-constant-time (`:458,:621`).
30. **[security] cmux socket path trusted from world-writable `/tmp`** (`TerminalJumpService.swift:578-602`); editor/tmux CLIs resolved via inherited PATH (`:1318-1332`).
31. **[correctness] Warp AX precision jump has no `AXIsProcessTrusted()` pre-check** and depends on a hardcoded English menu path (`KeystrokeInjector.swift:56-78,:65`); `WarpSQLiteReader` `busy_timeout` 60ms is very aggressive (`:528`).
32. **[maintainability] `AppModel` re-enumerates all 12 `AgentEvent` cases** in ≥2 switches (`:1541,:1796`) that should be a `sessionID`/`timestamp` property on the enum; tool-list membership hand-listed instead of using `AgentTool.isClaudeCodeFork` (`SessionState.swift:261-278`, `AgentSession.swift:511`).
33. **[correctness] `watchConnectedDevices` is a hardcoded `0` stub** shipped in an observable property (`AppModel.swift:465-468`); `TimedCache` never purges expired entries / no size cap (`TimedCache.swift:30-48`).

**Positives (hold up well):** fail-open honored on the hook CLI's main paths; 4MB frame cap correctly bounds `BridgeCodec.decodeLines`; `WatchHTTPEndpoint` request parsing is well-factored/defensive; CLI-based jumps (tmux/Zellij/WezTerm/VS Code/JetBrains) use argument arrays (no shell injection); cmux RPC escapes its surface id; `SessionStateTests` is thorough; 0 TODO/FIXME/HACK; only 2 boilerplate `fatalError`s.

## Risks & unknowns (resolve at/ before Plan)
- **Scope is far too large for one brief/PR.** This discovery spans every subsystem. Plan must slice it into independent, individually-approvable briefs (each its own `/octospec` cycle). Recommended cut, highest ROI first:
  1. **Security & robustness of the bridge** — #3 (writeAll timeout), #4 (socket auth/perms), #10 (Codable forward-compat). Small, high-impact, testable.
  2. **Reducer correctness/purity** — #1, #2, #11, #12 (+ injectable clock). Contained to `SessionState`, backed by existing test suite.
  3. **Installer safety** — #7 (OpenCode clobber), #19 (Cursor version), #20 (backup pruning), #21 (transactionality). User-data-facing.
  4. **De-duplication refactors** — #6 registries/installers/AppleScript/metadata. Large, mechanical, lower risk once 1-3 land; needs its own briefs.
  5. **Perf/battery** — #13, #14, #15, #16 (FSEvents, streaming, formatter hoisting).
  6. **UI decomposition + design tokens** — #5 (IslandPanelView), #17, #24. Largest, least urgent.
  7. **Quality gates** — #26 (strict concurrency + SwiftLint), #8 (coordinator/fail-open tests), #9 (guard debug PII).
- **Decision needed:** is the security posture (#4, #29, #30) in scope for this repo's threat model? Local-first single-user may accept local-process trust — but that should be an explicit decision, not an accident. Flag for the human at Plan.
- **Unknown:** whether the strict-concurrency-off + 26 `@unchecked Sendable` is a deliberate pragmatic choice or accumulated debt — affects how aggressively #26 should push. Confirm with maintainer.
- **Verification gaps:** findings #12, #16 (append-only assumption), #13 (fractional seconds) were reasoned from code, not reproduced at runtime; each remediation brief should add a failing test first.
