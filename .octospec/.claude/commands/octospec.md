---
description: octospec engineering loop — discover/plan/implement/verify/iterate/finish (+ approve/next/status/autopilot)
argument-hint: <phase> <slug>
---

You are the **octospec** command for this repo. `$ARGUMENTS` is `<phase> [slug]`.

This command is a **thin router**: it does not restate what each phase does — the
`octospec-workflow` skill is the single source of truth for the phase steps. Parse
the first whitespace-delimited token of `$ARGUMENTS` as `<phase>` and the rest as
the task description (for `discover`) or `<slug>` (for every other phase), then
execute that phase exactly as the `octospec-workflow` skill defines it.

## Phases (the six-phase loop)

- `discover <task>` — **Discover**: create the task branch (`feat/<slug>` off
  `origin/main`), then read-only exploration of the code the task will touch.
  Write and commit `.octospec/tasks/<slug>/discovery.md`. No spec, no code yet.
- `plan <slug>` — **Plan**: derive `.octospec/tasks/<slug>/spec.md` from the
  discovery (Goal / Load-bearing list / Out of scope / Acceptance). Set/keep
  `revision`, commit the spec. Show it and stop for human approval.
- `implement <slug>` — **Implement (TDD)**: FIRST check the approval gate (see
  below); then inject matching rules and follow **Red → Green → Refactor** — write
  the approved Acceptance as failing tests and commit them (`red: <slug>`) BEFORE
  production code, then write the minimal code to green, then refactor staying
  green. Do not edit tests to fake a pass.
- `verify <slug>` — **Verify**: dispatch an **independent reviewer** (fresh
  context — `code-reviewer`/`verifier`/`/review`) to check the diff against the
  spec's Acceptance + injected rules + Out of scope, **confirm the `red:` commit
  precedes the code and its tests encode the Acceptance** (green didn't weaken
  them), then run `manifest.verify.gate`. The implementing context must NOT
  self-certify.
- `iterate <slug>` — **Iterate** (optional): disciplined rework after a failed
  Verify. Impl/test-only fix → back to Verify (a test fix is its own explained
  commit). Spec-changing (incl. "an Acceptance item can't be a valid failing
  test") → bump the spec `revision`, add an Iteration Log entry, commit, and go
  back through the approval gate.
- `finish <slug>` — **Finish**: final gate, slim journal entry (one-line result +
  `## Learning`, no per-task log.md), land any reusable learning in this same PR,
  open the PR (Linked Spec + COMPREHENSION). The branch already carries the spec.
- `autopilot <slug>` — **Autopilot**: after approval, run Implement (Red→Green→
  Refactor) → Verify → (impl/test-only Iterate, ≤2 retries) → Finish
  **unattended**, stopping at "PR opened". Red still commits before code. Stops
  and returns to the human on a spec-changing failure (revision bump → needs
  re-approval) or when retries are exhausted. Refuses if the current revision is
  not approved. Never auto-merges.

## Gate + helpers

- `approve <slug>` — record human approval of the spec's **current** `revision`.
  Append to the spec's `approvals:` frontmatter an entry
  `{ revision: <current>, by: <git config user.name>, at: <ISO8601 UTC> }`, then
  **commit it** (`approve: <slug> r<current>`) so the sign-off is in git history.
  This is a **human action** — never run it to approve your own spec.
- `next <slug>` — read the task's state (does the task branch exist? `discovery.md`?
  `spec.md`? is the current revision approved? is there a diff? did Verify pass?)
  and run the next phase in the loop.
- `status <slug>` — **read-only**: report which phase the task is in, whether the
  current spec revision is approved, and what is blocking progress. Change nothing.

## Approval gate (enforced by `implement`)

Before writing any code, `implement` MUST confirm the spec's `approvals:` contains
an entry whose `revision` equals the spec's current `revision`. If it does not,
**refuse** and tell the user to review the spec and run `/octospec approve <slug>`
(or `/octospec plan <slug>` to revise). You must never write your own approval.

> Spec file: `.octospec/tasks/<slug>/spec.md` (renamed from `brief.md` in 2.1.0).
> When reading an existing task, fall back to a legacy `brief.md` if `spec.md` is
> absent (one release cycle); always write `spec.md`.

If `<phase>` is missing or unrecognized, list the phases above and stop.
