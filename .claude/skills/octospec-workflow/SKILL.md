---
name: octospec-workflow
description: >-
  Use when implementing a feature, fixing a bug, or making any non-trivial code
  change in this repository. Drives the octospec 6-phase engineering flow
  (Discover, Plan, Implement, Verify, Iterate, Finish) so the change follows this
  repo's rules in .octospec/ and ships a PR with a linked, human-approved spec.
  Triggers on requests like "add ...", "implement ...", "fix ...", "refactor ...",
  "change the ... API", 写功能, 修 bug, 加接口, 改逻辑. Skip for trivial edits
  (typo, docs, lint, pure config) — those do not need the flow.
---

# octospec workflow

This repository uses the **octospec** engineering standard. When you are asked to
make a non-trivial code change here, run the 6-phase flow instead of editing code
directly. Rules live in `.octospec/` and are the source of truth for this repo's
conventions.

This skill is the **single source of truth** for what each phase does. The
`/octospec <phase> <slug>` command is a thin router into these same steps.

## When to run this

Run the flow for: a new feature, a bug fix, a refactor, an API change, or any
change that touches load-bearing behavior.

**Do NOT run the flow** for trivial changes: a typo, a docs-only edit, a
lint-only fix, a pure config or dependency bump. Just make those directly.

## The loop

```
Discover → Plan → [approval gate] → Implement → Verify ──pass──→ Finish
              ▲                          ▲            │
              │                          │          fail
              │                          │            ▼
              └───── Iterate (spec-changing) ◄── Iterate (impl-only)
```

Run the phases in order. Each maps to `/octospec <phase> <slug>`, which the user
can also invoke manually.

### 1. Discover
- Choose a short kebab-case `<slug>`.
- Read `.octospec/tasks/_discovery.template.md`.
- **Read-only exploration**: inspect the code the task will touch — the
  load-bearing paths, their callers, contracts, isolation boundaries, blast
  radius. Do NOT write a brief or any code yet.
- Write `.octospec/tasks/<slug>/discovery.md`: Relevant files, Existing behavior,
  Contracts & blast radius, Risks & unknowns.
- Purpose: an accurate load-bearing list in the next phase (which is what makes
  the right rules get injected in Implement).

### 2. Plan
- Read `.octospec/tasks/_brief.template.md` and the `discovery.md` you just wrote.
- Write `.octospec/tasks/<slug>/brief.md` with OKF frontmatter (`type: Task` +
  title/description/tags/timestamp, and `revision: 1`, `approvals: []`):
  - **Goal** — what behavior changes and why.
  - **Load-bearing list** — derive it from `discovery.md`. Use the same tags as
    `.octospec/rules/_index.yaml` `inject_when.touches` where they apply.
  - **Out of scope** — what this deliberately does NOT touch.
  - **Acceptance** — machine-checkable where possible.
- **Show the brief and stop. It must be human-approved before Implement.**

### Approval gate (between Plan and Implement)

A brief may not proceed to Implement until a human has approved its **current**
`revision`. Approval is recorded in the brief's `approvals:` frontmatter:

```yaml
revision: 1
approvals:
  - revision: 1
    by: <git config user.name>
    at: <ISO8601 UTC>
```

- The human runs `/octospec approve <slug>`, which appends an approval entry for
  the current `revision`. **You must never write your own approval** — that would
  defeat the comprehension gate (no self-approval).
- Implement checks this gate as its first action (below).

### 3. Implement
- **Gate check first.** Read the brief's `revision` and `approvals`. Confirm an
  entry exists with `revision` == the current `revision`. If not, **refuse**:
  tell the user to review the brief and run `/octospec approve <slug>` (or
  `/octospec plan <slug>` to revise). Do not write any code until the gate passes.
- **Inject rules.** Read `.octospec/rules/_index.yaml` and `.octospec/_global/`
  (if synced). A rule applies when its `inject_when.paths` glob matches a file you
  will touch, OR its `inject_when.touches` tag is in the brief's load-bearing
  list. A repo-tier rule overrides a global one with the same id. **Read the full
  text of every matching rule and follow it; do load-bearing rules first.**
- Write the code following those rules. **Do not commit.**

### 4. Verify
- Review the diff against each injected rule (trace load-bearing paths, not just
  the happy path).
- Confirm the diff meets the brief's **Acceptance** and did not touch anything in
  **Out of scope**.
- Run this repo's gate: the commands in `manifest.yaml` `verify.gate`. If no
  `verify:` block is present, fall back to the gates named in CLAUDE.md / AGENTS.md
  (lint / type-check / tests).
- Self-fix what you can. If the gate passes and the diff is clean, go to Finish.
  If not, go to Iterate.

### 5. Iterate (optional)
Only when Verify failed or surfaced a gap. Decide the kind of rework:
- **Impl-only** (the brief was right; the code was wrong): fix the code and go
  back to Verify. Do NOT touch the brief. Do NOT bump `revision`.
- **Spec-changing** (the load-bearing list, goal, scope, or acceptance was wrong
  or incomplete): update the brief, **bump `revision`**, add an **Iteration Log**
  entry stating the semantic reason (not the diff), then go back through the
  **approval gate** — the bump invalidated the prior approval, so the new revision
  must be re-approved before Implement resumes.

### 6. Finish
- Run the `verify.gate` once more.
- Write `.octospec/journal/<slug>.md` (what was done + any learning). Start it with
  OKF frontmatter (`type: Journal` + title/description/tags/timestamp) and add a
  dated entry to `.octospec/log.md`.
- Promote any reusable learning **in this same PR**: edit the relevant
  `.octospec/rules/<rule>.md` in place (or add a new rule + `_index.yaml` entry) —
  the PR review is the gate. The helper `.octospec/scripts/octospec-update-spec.sh`
  gives you the raw material: `--kind=rule` → a draft in
  `learnings/pending/<slug>-rule-draft.md` + a promotion block on stdout. It never
  auto-writes `rules/`, so **you** copy the draft into `rules/<id>.md` and update
  `_index.yaml` here, in this PR, then drop the scratch draft. Only use
  `.octospec/learnings/pending/` for *unresolved* learnings that still need human
  design before becoming a rule; finished learnings must not be stranded there.
- Open a PR. Fill the PR template's **Linked Spec** (→ the brief, noting the
  approved revision) and the **COMPREHENSION** three questions to substance, for
  load-bearing / architectural / P0 changes.

## Notes

- `/octospec next <slug>` inspects task state (discovery? brief? approved? diff?
  verify result?) and runs the next phase for you.
- `/octospec status <slug>` reports the current phase and what is blocking,
  read-only.
- The flow is guidance; the repo's PR/CI checks are the enforcement layer. The
  approval gate is enforced by Implement refusing an unapproved revision.
