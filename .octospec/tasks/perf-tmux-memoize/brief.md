---
type: Task
title: "Task: perf-tmux-memoize"
description: Memoize the per-sweep tmux list-panes/list-clients queries in ActiveAgentProcessDiscovery so N tmux-attached agents cost 1 query pair, not N
tags: ["performance", "battery", "process-discovery", "tmux"]
timestamp: 2026-07-09T01:58:14Z
# --- octospec extension fields ---
slug: perf-tmux-memoize
upstream: arch-quality-audit-r2 (discovery finding #2, subprocess fan-out)
source: self
revision: 1
approvals:
  - revision: 1
    by: lml2468
    at: 2026-07-09T02:04:12Z
---

# Task: perf-tmux-memoize

> Seventh slice of the `arch-quality-audit-r2` discovery — the battery-focused
> half of finding #2 (FSEvents is a separate, larger refactor, out of scope).
> Independent branch off `origin/main`.

## Goal

`ActiveAgentProcessDiscovery.discover()` runs a full process sweep on the app's
monitoring cadence (every ~2s while active). For each agent whose terminal is
unresolved it calls `resolveTmuxInfo(agentTTY:…)`
(`ActiveAgentProcessDiscovery.swift:858`), which **per agent** runs `resolveTmuxPath`
+ `tmux list-panes -a` (`queryTmuxTarget:896`) + `tmux list-clients`
(`findTmuxClientTerminal:924`). But `list-panes -a` and `list-clients` return
**global** state — for N tmux-attached agents the same subprocesses run N times
producing byte-identical output. That is periodic fork/exec battery drain.

Fix: compute a **per-sweep tmux context once** (resolved tmux path, socket path,
a `paneTTY → target` map from one `list-panes`, and the host terminal from one
`list-clients`), then make the per-agent resolution a **pure dictionary lookup**
keyed by `agentTTY`. Build the context **lazily** — only when the first agent
actually needs tmux — so a sweep with no tmux-attached agents still issues zero
tmux subprocesses (preserving today's behavior).

## Background

- Only one thing in the tmux path is per-agent: the `ptrTTY == agentTTY` match in
  `queryTmuxTarget` (`:916`). Everything else (`resolveTmuxPath`, the tmux-server
  socket scan `:868-881`, the full pane list, and `findTmuxClientTerminal`'s host
  terminal — which takes **no** `agentTTY`) is global and identical across agents
  in a sweep.
- The 4 call sites (`:166` openCode inline, `:269` codex, `:304` cursor, `:371`
  claude) are each guarded by `if snapshot.terminalApp == nil, let agentTTY =
  process.terminalTTY`. The candidate process list (incl. any `tmux-server`) is
  already built before the loop, so the context can be produced lazily on first
  need.
- **Testable via the injected `CommandRunner` seam.** `init(commandRunner:)`
  (`:54`) takes `@Sendable (path, args) -> String?`; existing tests fake `/bin/ps`
  and `/usr/sbin/lsof`. Every tmux exec (`list-panes`, `list-clients`, and
  `resolveTmuxPath`'s `which` fallback) routes through `commandRunner`, so a
  counting wrapper can assert the query count.
- **Injected rule:** none currently indexed for this file — this slice may promote
  a small `process-discovery-perf` note or fold into an existing perf rule at
  Finish.

## Load-bearing list
<!-- touches: tags drive rule injection. -->
- **`resolveTmuxInfo`** (`:858-894`) — split into a global `makeTmuxContext(...)`
  (computed once) + a pure `resolveTmuxInfo(agentTTY:context:)` lookup.
  `[process-discovery] [tmux] [performance]`
- **`queryTmuxTarget`** (`:896-922`) — refactor to parse the pane list into a
  `[paneTTY: target]` map once (preserving the exact trim + `==` matching).
  `[tmux]`
- **`findTmuxClientTerminal`** (`:924-956`) and **`resolveTmuxPath`** (`:838-856`)
  — called once from `makeTmuxContext`. `[tmux]`
- **The 4 call sites** (`:166, :269, :304, :371`) + the `discover()` loop
  (`:69`) — thread the lazily-built context; the resolved
  `(terminalApp/hostTerminal, tmuxTarget, tmuxSocketPath)` per agent must be
  byte-identical to today. `[process-discovery]`

## Out of scope
- **FSEvents / replacing the poll model** (the other half of #2) — large refactor,
  separate.
- **The per-agent `lsof` fan-out** and the `ps` sweep — unchanged (those are
  genuinely per-process, not redundant).
- **`resolveTmuxPath`'s `FileManager.isExecutableFile` hardcoded-path check** —
  left as-is (making tmux-path candidates injectable is out of scope; tests assert
  only `list-panes`/`list-clients` counts, not `which`).
- No change to `ProcessSnapshot`, the `discover()` return shape, or non-tmux
  resolution paths.

## Acceptance
<!-- Each item stated so it can become a failing test in Implement's Red step. -->
- **A1 — N tmux-attached agents cost ≤1 `list-panes` and ≤1 `list-clients` per
  sweep.** With a faked `ps` containing two agents (Claude + Codex) on distinct
  TTYs both hosted only via tmux (`terminalApp` resolves to nil without tmux), a
  `tmux-server` process, and a client-tty process under a recognized terminal, one
  `discover()` invokes `commandRunner` with `list-panes` **≤1** time and
  `list-clients` **≤1** time (counted via a wrapper box). *(Testable: fails first —
  today both run twice, once per agent.)*
- **A2 — per-agent correctness preserved.** In that same fixture, each agent's
  snapshot gets its **own** correct `tmuxTarget` (distinct, from the pane map) plus
  the shared `terminalApp`/host and `tmuxSocketPath`. *(Testable: guards against
  the memo returning one agent's target for both. Passes before and after —
  behavior preservation.)*
- **A3 — no-tmux sweeps issue zero tmux subprocesses.** With a fixture whose
  agents resolve their terminal directly (no tmux), `discover()` invokes
  `commandRunner` with `list-panes` **0** times and `list-clients` **0** times
  (the lazy short-circuit is preserved). *(Testable: protects the common path from
  a regression where the context is built eagerly.)*
- **A4 — gate is green.** `swift build` + `swift test` pass under the repo gate
  (warnings-as-errors + `swiftlint --strict`). *(N/A(test): the gate itself.)*

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec. -->
