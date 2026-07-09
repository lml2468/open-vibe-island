---
type: Journal
title: "Journal: perf-tmux-memoize"
description: Memoized the per-sweep tmux list-panes/list-clients queries so N tmux-attached agents cost one query pair per sweep, not N
tags: ["performance", "battery", "process-discovery", "tmux"]
timestamp: 2026-07-09T02:15:00Z
slug: perf-tmux-memoize
source: self
---

# Journal: perf-tmux-memoize

Seventh implemented slice of the `arch-quality-audit-r2` discovery — the
battery-focused half of finding #2 (FSEvents left out of scope).

## What was done

`ActiveAgentProcessDiscovery.discover()` runs every ~2s and called
`resolveTmuxInfo` per tmux-attached agent, each running `resolveTmuxPath` +
`tmux list-panes -a` + `tmux list-clients`. Those queries return **global** state,
so N agents produced N identical query pairs. Introduced a lazy per-sweep
`TmuxSweepContext` (resolved path + socket + a `paneTTY → target` map from one
`list-panes` + host terminal from one `list-clients`), computed at most once and
only when an agent actually needs tmux. `resolveTmuxInfo` became a pure lookup
against that context, and a shared `applyTmuxInfo` helper replaced the four
duplicated per-agent tmux blocks (codex/claude/cursor builders + the openCode
inline branch). N agents now cost one `list-panes` + one `list-clients` per sweep.

## Verification

- New `ActiveAgentProcessDiscoveryTmuxTests` (3), driven by the injected
  `commandRunner` with a counting box: A1 two tmux agents → `list-panes` ≤1 and
  `list-clients` ≤1 per sweep (failed first: 2 each); A2 each agent keeps its own
  distinct `tmuxTarget` + shared host/socket; A3 a no-tmux sweep issues 0 tmux
  subprocesses (lazy short-circuit preserved).
- TDD trail: `red:` added only the test (A1 fails, A2/A3 characterize); Green
  touched only the source (`git diff red..green -- Tests/` = 0 bytes).
- Independent Verify (fresh context) PASS — re-ran red to confirm the 2/2 failure,
  verified the memo caches even the nil-tmux result, laziness, and byte-identical
  original semantics (both-guards, first-match-per-TTY, socket scan). Existing
  non-tmux discovery tests still pass. Gate green: `harness.sh ci` (424 tests),
  warnings-as-errors + `swiftlint --strict`, exit 0.

## Learning

- **Hoist per-sweep global subprocess queries out of the per-item loop.** The tell
  was that `list-panes -a` / `list-clients` take a global scope but were called
  inside a per-agent path — only the final `paneTTY == agentTTY` match was
  per-agent. Split "global work computed once" from "pure per-item lookup" and the
  N× fork/exec collapses to 1×. For an always-on app polling every ~2s this is
  direct battery savings. Captured as the `process-discovery-perf` rule.
- **Memoize the negative result too.** The lazy context cache is a double-optional
  (`TmuxSweepContext??`): the outer optional means "computed yet?", so a nil-tmux
  outcome is cached as `.some(nil)` and not recomputed for every subsequent agent.
  A single-optional memo would re-run `resolveTmuxPath` per agent on machines
  without tmux — the exact fan-out being removed.
- **Assert ≤1, not ==1, for a "run at most once" perf property.** A sweep where no
  pane matches could now run `list-clients` once where the old short-circuit
  wouldn't have — still a win and still bounded. `≤1` is robust to that ordering;
  `==1` would be brittle. And assert only the queries that always route through
  the injected runner (`list-panes`/`list-clients`), not the `which` fallback,
  which `resolveTmuxPath` may skip via a real `FileManager` check.
