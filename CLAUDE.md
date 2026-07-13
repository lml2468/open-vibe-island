# CLAUDE.md

## Project

Open Island — native macOS companion for AI coding agents. Sits in the notch / top bar, monitors local sessions, surfaces permission and question events, and jumps back to the right terminal/IDE. Local-first, no server.

- **Target product** (closed-source baseline): https://vibeisland.app/
- **OSS reference** (design ideas only, not a spec): https://github.com/farouqaldori/claude-island

## Architecture

One Swift package (`OpenIsland`), four targets:

- **OpenIslandApp** — SwiftUI + AppKit shell. `AppModel` owns state.
- **OpenIslandCore** — Models, bridge transport (Unix socket, NDJSON), hook installers, session discovery & registry.
- **OpenIslandHooks** — CLI invoked by agent hooks. Forwards stdin payload → bridge.
- **OpenIslandSetup** — Installer CLI for agent config files.

Data flow: `agent hook → OpenIslandHooks (stdin) → Unix socket → BridgeServer → AppModel → UI`. On launch: registry restore → JSONL transcript discovery → reconcile with active processes → live bridge.

Requires macOS 14+, Swift 6.2.

## Build & run

```bash
swift build
swift test
swift run OpenIslandApp                            # canonical dev runtime
swift build -c release --product OpenIslandHooks
```

For Xcode: open `Package.swift`.

## Dev app (Open Island Dev.app)

`~/Applications/Open Island Dev.app` is a wrapper around the repo build, not a separate product.

- **Launch**: `zsh scripts/launch-dev-app.sh` — never just `open -na`, the bundle goes stale.
- **One-time signing**: `zsh scripts/setup-dev-signing.sh` — without this every rebuild changes cdhash and silently invalidates TCC grants (Accessibility, Automation). Required for any AX-touching feature (precision jump, keystroke/menu injection).
- `scripts/harness.sh smoke` / `scripts/smoke-dev-app.sh` are for deterministic harness runs only.

## Workflow

- **Never edit in the main worktree.** Use `EnterWorktree` (preferred) or `git worktree add`, branched off latest local `main`.
- Branch name matches topic: `feat/<topic>`, `fix/<topic>`. One coherent change per round.
- `main` is protected — direct push is rejected. All changes ship via PR **targeting `main`**. No chain PRs (A → B → main) — wait for the dependency to merge, then rebase.
- Conventional commit messages (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Never `--amend` unless asked.
- After changes: run the matching verification (`swift build` / `swift test` / manual). If no check exists, say so in the summary and still commit.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval. If unexpected state appears, inspect — don't bulldoze.

## Scope guardrails

Current support matrix (agents / terminals / IDEs) lives in `README.md` — that's the single source of truth, keep it accurate at release time.

The project is past MVP and welcomes new ideas and creative directions, but the following stay off-limits without an explicit ask:

- Analytics or telemetry SDKs (Mixpanel etc.)
- Window-manager dependencies (`yabai` etc.)
- Claude-only assumptions that weaken the multi-agent model
- Anything that breaks local-first (remote-server dependencies, cloud-only paths)

## Release

- Triggered by pushing a `v*` tag to `main`. CI builds, signs, notarizes, publishes the DMG. Don't create the GitHub release manually — edit the draft CI produces.
- Before tagging: `git fetch origin main` and review every merged PR since the last tag. Don't trust memory.
- Bilingual required (English + 简体中文). Template: `.github/RELEASE_TEMPLATE.md`. Entry format: `- **Category**: English (#PR)\n  中文 (#PR)`. External contributors get `— Thanks @user` on the English line.
- Title: `Open Island vX.Y.Z — Short English Title`. Installation section bilingual.

## Conventions

- `SessionState.apply(_:)` is the single source of truth for session mutations.
- Bridge protocol: newline-delimited JSON envelopes (`BridgeCodec`).
- All models `Sendable` + `Codable`.
- Hooks **fail open** — if app/bridge is down, the agent runs unchanged.
- Native macOS APIs over cross-platform abstractions. Small end-to-end slices over speculative scaffolding.

## Key files

- `Sources/OpenIslandApp/AppModel.swift` — central state, session management, bridge lifecycle
- `Sources/OpenIslandCore/SessionState.swift` — pure reducer
- `Sources/OpenIslandCore/AgentEvent.swift` — event enum driving all transitions
- `Sources/OpenIslandCore/BridgeTransport.swift` + `BridgeServer.swift` — socket protocol & dispatch
- `Sources/OpenIslandCore/{Claude,Codex,Gemini,Kimi,Cursor}Hooks.swift` etc. — per-agent hook payload models
- `Sources/OpenIslandHooks/main.swift` — hook CLI entry
- `docs/product.md`, `docs/architecture.md`, `AGENTS.md` — design / working-agreement docs

<!-- octospec:begin -->
## octo-spec engineering standard

This repo carries a shared engineering standard in `.octospec/`, readable by any
coding agent working in this checkout (Claude Code, Codex, OpenClaw, Gemini, or
others). **Follow it for any non-trivial change.**

When you take on a coding task here:

1. **Discover.** Read the code the task touches (read-only) and capture what you
   found in `.octospec/tasks/<slug>/discovery.md`. This grounds the load-bearing
   list so the right rules get injected.
2. **Plan → spec.** Derive `.octospec/tasks/<slug>/spec.md` from discovery:
   goal / load-bearing list / out-of-scope / acceptance
   (template: `.octospec/tasks/_spec.template.md`). A human **approves** the
   spec (records an approval for its `revision`) before you implement.
3. **Inject the rules that apply.** Read `.octospec/rules/` (index:
   `.octospec/rules/_index.yaml`) plus the inherited global rules in
   `.octospec/_global/`. A rule applies when its `inject_when.paths` matches a
   file you will touch, OR its `inject_when.touches` tag is in the spec's
   load-bearing list. **Read and follow the full text** of each matching rule
   before writing code; prioritize `load_bearing: true` rules.
4. **Implement (TDD).** Only after the current spec revision is approved. For a
   behavior change, write the approved acceptance as **failing tests first and
   commit them (`red: <slug>`) before production code** (Red), then the minimal
   code to green, then refactor while green. A change that genuinely can't carry a
   failing test uses an explicit `N/A(test): <reason>` in the spec — never a
   silent skip.
5. **Verify — independently.** A **fresh context** (not the one that wrote the
   code) checks the diff against each injected rule and the spec's acceptance,
   confirms the `red:`-before-code trail, and runs the repo's gate
   (`manifest.yaml` `verify.gate`, else CLAUDE.md gates). No self-certifying.
   Rework via **Iterate** if it fails (spec-changing rework re-triggers approval).
6. **Finish:** journal the work (flat `.octospec/journal/<slug>.md`: one-line
   Result + `## Learning`), land any reusable learning in this same PR, and open a
   PR filling **Linked Spec** + the **COMPREHENSION** three questions for
   load-bearing / architectural / P0 changes. Trivial changes
   (typo/docs/lint/config) are exempt.

Claude Code users drive this with one command: `/octospec <phase> <slug>`
(`discover|plan|implement|verify|iterate|finish`, plus `approve`, `next`,
`status`, and `autopilot` to run implement→verify→finish after approval) —
committed under `.claude/commands/`. Other agents read the same `.octospec/`
files directly — the steps above are the same regardless of tool.

The first time you apply this in a session, tell the user in one line that this
repo follows the octo-spec standard and point them at `.octospec/` (and
`docs/` in the octo-spec repo) for detail.

This region is managed by octospec-sync; edit outside the markers.
<!-- octospec:end -->
