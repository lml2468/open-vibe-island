---
type: Rule
title: Process discovery performance
description: The always-on process/terminal discovery sweep must not fan out redundant global subprocess queries per agent — hoist per-sweep global work out of the per-item loop and memoize it (negative results included).
tags: ["performance", "battery", "process-discovery", "subprocess"]
timestamp: 2026-07-09T02:15:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: process-discovery-perf
tier: repo
priority: 78
load_bearing: false
inject_when:
  paths:
    - "Sources/OpenIslandApp/ActiveAgentProcessDiscovery.swift"
  touches: ["process-discovery"]
source: self
supersedes: []
---

# Process discovery performance

`ActiveAgentProcessDiscovery.discover()` runs on the monitoring cadence
(every ~2s while active) over every running process. Subprocess fan-out here is
direct, repeated battery cost — keep it minimal.

## Hoist per-sweep global queries out of the per-agent loop

- If a subprocess returns **global** state (e.g. `tmux list-panes -a`,
  `tmux list-clients`) but is currently called inside a per-agent path, it runs N
  times for N agents producing identical output. Compute it **once per sweep**
  into a small context, and make the per-agent step a **pure lookup** against that
  context (the only per-agent part of the tmux path was the `paneTTY == agentTTY`
  match).
- Genuinely per-process queries (`lsof -p <pid>`, the `ps` sweep itself) are NOT
  redundant — leave them.

## Compute lazily, and memoize the negative result

- Build the per-sweep context **lazily** — only when the first agent actually
  needs it — so a sweep with nothing to resolve issues zero extra subprocesses.
- Memoize with a double-optional (`Context??`): the outer optional records
  "computed yet?", so even a `nil` outcome (tool absent) is cached and not
  recomputed for every subsequent agent. A single-optional memo silently re-runs
  the (possibly `FileManager`/`which`) resolution per agent — the fan-out you were
  removing.

## Testing the fan-out reduction

- Everything runnable goes through the injected `commandRunner` seam. Assert the
  query count with a reference counting box captured by the `@Sendable` closure.
- Assert **≤1** per sweep, not `==1`: a no-match sweep may legitimately run one
  extra global query the old short-circuit skipped — still bounded. Count only
  queries that always route through `commandRunner` (`list-panes`/`list-clients`),
  not the `which` fallback (`resolveTmuxPath` may satisfy it via a real
  `FileManager.isExecutableFile` check, so it's host-dependent).
