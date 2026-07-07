---
description: octospec engineering loop — discover/plan/implement/verify/iterate/finish (+ approve/next/status)
argument-hint: <phase> <slug>
---

You are the **octospec** command for this repo. `$ARGUMENTS` is `<phase> [slug]`.

This command is a **thin router**: it does not restate what each phase does — the
`octospec-workflow` skill is the single source of truth for the phase steps. Parse
the first whitespace-delimited token of `$ARGUMENTS` as `<phase>` and the rest as
the task description (for `discover`) or `<slug>` (for every other phase), then
execute that phase exactly as the `octospec-workflow` skill defines it.

## Phases (the six-phase loop)

- `discover <task>` — **Discover**: read-only exploration of the code the task will
  touch. Write `.octospec/tasks/<slug>/discovery.md`. No brief, no code yet.
- `plan <slug>` — **Plan**: derive `.octospec/tasks/<slug>/brief.md` from the
  discovery (Goal / Load-bearing list / Out of scope / Acceptance). Set/keep
  `revision`. Show it and stop for human approval.
- `implement <slug>` — **Implement**: FIRST check the approval gate (see below);
  only then inject matching rules and write code. Do not commit.
- `verify <slug>` — **Verify**: check the diff against injected rules + the brief's
  Acceptance, then run `manifest.verify.gate`. Report what you cannot fix.
- `iterate <slug>` — **Iterate** (optional): disciplined rework after a failed
  Verify. Impl-only fix → back to Verify. Spec-changing → bump the brief
  `revision`, add an Iteration Log entry, and go back through the approval gate.
- `finish <slug>` — **Finish**: final gate, journal entry, land any reusable
  learning in this same PR, open the PR (Linked Spec + COMPREHENSION).

## Gate + helpers

- `approve <slug>` — record human approval of the brief's **current** `revision`.
  Append to the brief's `approvals:` frontmatter an entry
  `{ revision: <current>, by: <git config user.name>, at: <ISO8601 UTC> }`.
  This is a **human action** — never run it to approve your own brief.
- `next <slug>` — read the task's state (does `discovery.md` exist? `brief.md`?
  is the current revision approved? is there a diff? did Verify pass?) and run the
  next phase in the loop.
- `status <slug>` — **read-only**: report which phase the task is in, whether the
  current brief revision is approved, and what is blocking progress. Change nothing.

## Approval gate (enforced by `implement`)

Before writing any code, `implement` MUST confirm the brief's `approvals:` contains
an entry whose `revision` equals the brief's current `revision`. If it does not,
**refuse** and tell the user to review the brief and run `/octospec approve <slug>`
(or `/octospec plan <slug>` to revise). You must never write your own approval.

If `<phase>` is missing or unrecognized, list the phases above and stop.
