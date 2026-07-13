---
name: octospec-init
description: >-
  Use the FIRST time you bring the octospec engineering standard into a repo
  that does not have it yet — to onboard octospec / initialize octospec into a
  fresh checkout. Triggers on requests like "onboard octospec", "initialize
  octospec", "set up octospec here", "add the octo-spec standard to this repo",
  在这个仓库接入 octospec, 启用 octo-spec 标准, 初始化 .octospec。 This is a
  one-time接入引导: copy the template, pin the global version, run the sync
  script, confirm the root `.claude/` scaffolding materialized, and self-check
  with lint.
  Once the repo already has a working `.octospec/`, stop using this skill — the
  day-to-day 6-phase flow is owned by the octospec-workflow skill instead.
---

# octospec-init (onboarding)

This skill is the **one-time接入引导** for the **octospec** engineering standard.
Run it when a repo does NOT yet carry `.octospec/` and you want to add it. There
is no onboarding CLI subcommand or flag to invoke — onboarding is simply the
handful of real shell steps below, run by hand.

> Relationship: **init = one-time onboarding** (this skill). Once `.octospec/`
> exists and syncs cleanly, day-to-day work hands off to the **octospec-workflow**
> skill (the runtime 6-phase flow: Discover, Plan, Implement, Verify, Iterate,
> Finish). The two do
> not overlap — init wires the repo up, workflow drives changes afterward.

## When to run this

Run it when:
- the repo has no `.octospec/` directory yet, and
- you want this repo to follow the octo-spec shared standard.

Do NOT run it if `.octospec/` already exists and `octospec-sync.sh` succeeds —
that repo is already onboarded; switch to the octospec-workflow skill.

## Steps

### 1. Copy the template skeleton

Copy `templates/octospec-init` from an octo-spec checkout into `.octospec/` at
the root of the target repo. This carries the rules index, task/journal
scaffolding, the `.claude/` commands + skills, and its own `scripts/` (so the
synced repo holds the sync tooling itself).

```bash
cp -r <path-to>/octo-spec/templates/octospec-init .octospec
```

### 2. Pin the global version and fill in metadata

Edit `.octospec/manifest.yaml`:
- Pin the global ("constitution") version you inherit:
  `inherits: octo-spec@<semver>` — use the exact version of the octo-spec
  checkout you are syncing from. Read it from that checkout's `VERSION` file
  (`cat <path-to>/octo-spec/VERSION`) rather than hardcoding a number here, so
  this instruction never drifts when octo-spec bumps its version. For example,
  if `VERSION` says `2.1.0`, set `inherits: octo-spec@2.1.0`. The pin must match
  the `GLOBAL_SRC` checkout's `VERSION` exactly or `octospec-sync.sh` fails the
  version assertion. The template manifest already ships pinned to this
  checkout's version, so when you sync from the same checkout no edit is needed.
- Set `tier` (default `repo` — the global layer lives in octo-spec itself).
- Set `owner` to the team or person responsible for this repo's `.octospec/`.

### 3. Sync

Run the sync script with `GLOBAL_SRC` pointing at a checkout of octo-spec **at
the pinned version**. `GLOBAL_SRC` is mandatory: if it is unset the script prints
guidance and exits 1.

```bash
GLOBAL_SRC=/path/to/octo-spec ./.octospec/scripts/octospec-sync.sh
```

This vendors the pinned global rules into the git-ignored cache
`.octospec/_global/` (the script adds `_global/` to `.octospec/.gitignore`
automatically) AND materializes the repo-root scaffolding that tools only
discover at the root:
- copies `.octospec/.claude/` to the repo root `.claude/` so Claude Code finds
  the `/octospec <phase> <slug>` command (phases:
  `discover|plan|implement|verify|iterate|finish`, plus `approve|next|status|autopilot`)
  and the workflow skill, and
- copies `.octospec/.github/PULL_REQUEST_TEMPLATE.md` to `.github/` so GitHub
  applies the PR template (the body the Finish phase pre-fills).

octospec is **Claude-only**: it is discovered through the Claude Code skill +
command under `.claude/`. Sync does **not** write `CLAUDE.md` / `AGENTS.md` /
`GEMINI.md` / `QWEN.md` — there is no injected instruction block. (Multi-agent
distribution — shipping the skill into other agents' native skill dirs — is a
future addition, not part of this flow.)

At the root, sync uses **two policies**: octospec-managed files (the `octospec`
command, the `octospec-*` skills, the PR template) are **refreshed from source**
every run so upgrades land; a file you authored yourself under `.claude/` is
**install-if-missing** and left untouched. Re-running sync is idempotent. It also
**prunes** octospec-managed root commands (`.claude/commands/octospec*.md`) that
the pinned version no longer ships (never your own commands). Commit the
materialized root `.claude/` and `.github/` so teammates get them on a plain
`git pull`.

> **Upgrading is one step.** Sync **refreshes the octospec-managed surfaces** —
> the vendored `.octospec/.claude/` + `.octospec/.github/` + fill-in templates,
> AND the materialized repo-root skill / command / PR template — from `GLOBAL_SRC`
> every run (the same freshness model as `_global/`). So to move to a newer
> octo-spec you only bump `inherits:` in `manifest.yaml` and re-run sync from the
> matching checkout: the new command/skill/PR-template land at the root and
> obsolete commands are pruned automatically. The one surface sync can't refresh
> in place is `.octospec/scripts/` itself (it is the running script) — re-copy the
> template `scripts/` on a tooling upgrade. Your own content (`manifest.yaml`,
> real `tasks/`, `journal/`, `rules/`, and any non-octospec files under
> `.claude/`) is never touched.

### 4. Confirm the scaffolding materialized

Confirm sync placed the Claude Code entry points at the repo root:
- `.claude/commands/octospec.md` — the `/octospec <phase> <slug>` command.
- `.claude/skills/octospec-workflow/SKILL.md` — the workflow skill (the single
  source of truth for the 6-phase flow).
- `.github/PULL_REQUEST_TEMPLATE.md` — the PR template.

Sync never touches `CLAUDE.md`/`AGENTS.md`, so there is no instruction block to
verify — the skill is what Claude Code auto-discovers.

### 5. Self-check with lint

Run the OKF conformance lint once, from the repo root of the target repo, using
the lint script in your octo-spec checkout (the same `GLOBAL_SRC` you synced from
in step 3). Unlike `octospec-sync.sh`, the lint script is **not** vendored into
`.octospec/scripts/` — it is a one-time onboarding self-check, so it is run from
the octo-spec checkout rather than copied into every repo.

```bash
GLOBAL_SRC=/path/to/octo-spec   # the checkout you synced from in step 3
"$GLOBAL_SRC/scripts/octospec-lint.sh" .
```

Exit 0 means the knowledge units conform. The linter recurses from `.`, so it
picks up this repo's `.octospec/rules/` (it scans OKF knowledge units under
`global/`, `*/rules/`, `tasks/`, and `journal/`; it does not inspect skill files,
so this skill itself is out of scope).

## After onboarding

Once the steps above pass, this repo is onboarded. Hand day-to-day coding back to
the **octospec-workflow** skill, which runs the 6-phase flow for each non-trivial
change. Re-run step 3 (sync) any time you bump the pin in `manifest.yaml` — it is
idempotent.
