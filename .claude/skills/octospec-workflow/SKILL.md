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
Discover → Plan → [approval gate] → Implement ─────────→ Verify ──pass──→ Finish
   │          ▲                     (Red→Green→Refactor)     │
 branch       │                          ▲                 fail
 + spec       │                          │                   ▼
 commits      └──── Iterate (spec-changing) ◄── Iterate (impl/test-only)
```

Run the phases in order. Each maps to `/octospec <phase> <slug>`, which the user
can also invoke manually. **Two things need a human: `approve` (the scope
sign-off) and merging the PR. Everything between them can run unattended** — see
**Autopilot** below.

Implement follows **TDD (Red → Green → Refactor)** for behavior changes: the
approved Acceptance is first written as a *failing* test and committed **before**
any production code (Red), so the pass later proves the behavior, not the author's
say-so. See phase 3.

The task's own **git branch** is created at Discover and carries every artifact:
discovery, spec, the approval record, and the code all land as commits on it, so
the PR opened at Finish already contains the spec — nothing is copied by hand.

### 1. Discover
- Choose a short kebab-case `<slug>`.
- **Create the task branch** off the latest mainline (`git fetch origin`, then
  `git switch -c feat/<slug> origin/main`, or this repo's branch convention).
  Everything from here lands on this branch, so the PR carries the spec.
- Read `.octospec/tasks/_discovery.template.md`.
- **Read-only exploration**: inspect the code the task will touch — the
  load-bearing paths, their callers, contracts, isolation boundaries, blast
  radius. Do NOT write a spec or any code yet.
- Write `.octospec/tasks/<slug>/discovery.md`: Relevant files, Existing behavior,
  Contracts & blast radius, Risks & unknowns. **Commit it**
  (`discover: <slug>`).
- Purpose: an accurate load-bearing list in the next phase (which is what makes
  the right rules get injected in Implement).

### 2. Plan
- Read `.octospec/tasks/_spec.template.md` and the `discovery.md` you just wrote.
- Write `.octospec/tasks/<slug>/spec.md` with OKF frontmatter (`type: Task` +
  title/description/tags/timestamp, `revision: 1`, and a bare `approvals:` key —
  an empty block sequence, NOT `approvals: []`, so the approve step can append a
  block item as valid YAML):
  - **Goal** — what behavior changes and why.
  - **Load-bearing list** — derive it from `discovery.md`. Use the same tags as
    `.octospec/rules/_index.yaml` `inject_when.touches` where they apply.
  - **Out of scope** — what this deliberately does NOT touch.
  - **Acceptance** — each item stated so it can become a **failing test** in
    Implement's Red step. For a behavior change this is the default; an item that
    genuinely cannot have an automated failing test (pure refactor, UI/visual,
    config/dependency bump) must be marked `N/A(test)` with a one-line reason.
    That reason is the honest exemption — silently skipping the test is not
    allowed, and it is what the independent Verify checks against.
- **Commit the spec** (`plan: <slug> r1`).
- **Show the spec and stop. It must be human-approved before Implement.**

### Approval gate (between Plan and Implement)

A spec may not proceed to Implement until a human has approved its **current**
`revision`. Approval is recorded in the spec's `approvals:` frontmatter:

```yaml
revision: 1
approvals:
  - revision: 1
    by: <git config user.name>
    at: <ISO8601 UTC>
```

- The human runs `/octospec approve <slug>`, which appends an approval entry for
  the current `revision` **and commits it** (`approve: <slug> r<rev>`) so the
  sign-off is tamper-evident in git history. **You must never write your own
  approval** — that would defeat the comprehension gate (no self-approval).
- Implement checks this gate as its first action (below).

### Slice classification (decide once, per slice)

Not every slice is a behavior change, and forcing one Red→Green shape on all of
them is what produces hollow tests. Classify the slice — in the spec's Acceptance
— into exactly one of three kinds. The class fixes both the Red obligation and the
Verify criterion:

| Class | What it is | Acceptance mark | Verify criterion |
|---|---|---|---|
| **behavior-change** | changes observable behavior | testable items (default) | standard Red→Green — the Red test must fail on an **assertion**, then pass |
| **pure-relocation** | moves code, behavior unchanged (extract, rename, inline) | `N/A(test): relocation` | **byte-equivalent** behavior diff + the existing suite stays green |
| **characterization** | pins down *current* (possibly undocumented) behavior so a later slice can refactor safely | `N/A(test-first): characterization` | assertions are **discriminating** (see below) and would catch the regression the next slice risks |

A single task is usually one class. If it genuinely spans two (e.g. add behavior
*and* relocate), split it into two slices — that is the point of slicing.

#### characterization-first (two-stage, named — don't reinvent per slice)

When the code you need to refactor **has no direct tests**, do not try to
Red→Green the refactor. Use the two-stage pattern:

1. **Net slice** (characterization): land an independent PR that adds a
   *characterization net* — tests that pin the code's **current** behavior green
   (whatever it is today, warts included). This slice is class `characterization`.
2. **Extract slice** (pure-relocation): with the net in place, do the actual
   extract/refactor in a second PR. Its Verify is `pure-relocation`: the net
   stays green **and** the behavior diff is byte-equivalent.

The net PR ships first and stands on its own, so the risky extract is done under a
safety net that already merged — never in the same unprotected step.

### 3. Implement — TDD (Red → Green → Refactor)
- **Gate check first.** Read the spec's `revision` and `approvals`. Confirm an
  entry exists with `revision` == the current `revision`. If not, **refuse**:
  tell the user to review the spec and run `/octospec approve <slug>` (or
  `/octospec plan <slug>` to revise). Do not write any code until the gate passes.
- **Inject rules.** Read `.octospec/rules/_index.yaml` and `.octospec/_global/`
  (if synced). A rule applies when its `inject_when.paths` glob matches a file you
  will touch, OR its `inject_when.touches` tag is in the spec's load-bearing
  list. A repo-tier rule overrides a global one with the same id. **Read the full
  text of every matching rule and follow it; do load-bearing rules first.**
- **Red — write the failing tests first.** Translate each testable Acceptance
  item into a test and run it. Confirm it fails **for the right reason** (the
  behavior is missing / wrong — not a compile error, typo, or missing import).
  **Commit the failing tests on their own** (`red: <slug>`) *before* writing any
  production code — this red commit is the pre-registered, git-provable anchor the
  independent Verify checks against.
  - Acceptance items marked `N/A(test)` / `N/A(test-first)` in the spec have no
    behavior-change Red test (see Slice classification). If, while writing tests,
    you find an Acceptance item is wrong or untestable as written, that is a
    **spec-changing** signal → Iterate (do not quietly weaken it).
  - **Red self-check — run these before committing the `red:` commit.** These are
    the failure modes that otherwise slip through to Verify; catch them here:
    a. **Assertion, not accident.** The failure must be an *assertion* failure,
       not a compile error or a crash. Guard any crash point (e.g. index a
       stub's return with `.first` + a `guard`, not `[0]`) so the test reaches
       the assertion instead of trapping.
    b. **It actually reaches the code under test.** Before trusting a
       characterization test, confirm the fixture drives a path the callee really
       traverses (read the callee's traversal / dispatch set) — a green test that
       never entered the target verifies nothing.
    c. **Discriminating.** For an identity / no-op branch, the fixture must make
       the identity result **differ** from any result the regression would
       produce — otherwise "pass" and "regressed" look identical and the test
       can't tell them apart.
    d. **Real signatures.** Before referencing an external symbol, verify its
       actual signature (parameter order, enum case names, visibility, static
       member prefix) — guessing produces a compile error masquerading as Red.
- **Green — minimal code to pass.** Write the least production code that turns the
  red tests green, following the injected rules. Do **not** edit the tests to make
  them pass; if a test itself was wrong, that is Iterate (test-only), and the fix
  is a separate, explained commit — not a silent weakening buried in the green
  diff.
  - **Filter, not full gate, during the Red→Green loop.** While driving tests to
    green, run only the **targeted filter** (just this slice's tests), not the
    whole suite — it's the fast inner loop. Save the **full `verify.gate`** for
    Finish (and Verify). Don't burn a full-suite run on every Green iteration.
- **Refactor — clean up while staying green.** With the tests green, improve the
  code (naming, duplication, structure) and re-run the targeted filter to confirm
  it stays green. No behavior change here. (Refactor is part of Implement, not a
  separate phase.)
- Commit the production code + refactor on the task branch (after the `red:`
  commit).

### 4. Verify — an independent pass, not self-review
Verify is a **separate, fresh-context review**, not the implementing context
grading its own homework (that violates the "never self-approve in the same
active context" rule). The context that wrote the code must NOT self-certify.

**Tier the effort by slice class** — a full independent agent on a pure move is
waste; a diff-check on a behavior change is negligence:

- **behavior-change → full independent reviewer.** Launch a fresh-context subagent
  (`code-reviewer` / `verifier`, or the `/review` skill) with only: the diff, the
  spec's **Acceptance**, the injected rules, and the **Out of scope** list. It
  checks the diff against each — tracing load-bearing paths, not just the happy
  path — confirms nothing in Out of scope was touched, and checks the TDD trail
  (below).
- **pure-relocation → lightweight diff-only check.** No full agent. Confirm the
  behavior diff is **byte-equivalent** (a scriptable/normalized diff of the moved
  code) and the existing suite stays green. Escalate to a full reviewer only if
  the diff is *not* clean-equivalent (i.e. it turned out not to be pure).
- **characterization → focused independent review.** A fresh reviewer, but scoped
  to one question: are the assertions **discriminating** and do they capture the
  regression the next slice risks? (Not a broad correctness sweep — the behavior
  is whatever exists today.)

**TDD-trail check** (for behavior-change; git history is the evidence):
  - a `red:` commit exists **before** the production code, and its tests actually
    failed on the pre-implementation tree;
  - those tests genuinely **encode the approved Acceptance** (not a weaker or
    tautological version);
  - the green diff did **not** edit the tests to fake a pass (any test change is a
    separately explained Iterate commit, not smuggled into Green);
  - every non-`N/A` Acceptance item has a corresponding test.

- **Run the full gate.** Run this repo's gate: the commands in `manifest.yaml`
  `verify.gate` (the full suite — this is the run the Red→Green loop's targeted
  filter deliberately deferred). If no `verify:` block is present, fall back to the
  gates named in CLAUDE.md / AGENTS.md (lint / type-check / tests).
- If the review is clean **and** the gate passes, go to Finish. Otherwise go to
  Iterate (fixes are the implementer's job; re-review after).

### 5. Iterate (optional)
Only when Verify failed or surfaced a gap. Decide the kind of rework:
- **Impl/test-only** (the spec was right; the code or a test was wrong): fix it
  and go back to Verify. A test fix must be its **own commit** with a one-line
  reason (so it is never mistaken for weakening a test to fake green). Do NOT
  touch the spec. Do NOT bump `revision`. Under Autopilot this retries at most
  **twice** before stopping for a human.
- **Spec-changing** (the load-bearing list, goal, scope, or acceptance was wrong
  or incomplete — including "an Acceptance item can't be made a valid failing
  test"): update the spec, **bump `revision`**, add an **Iteration Log** entry
  stating the semantic reason (not the diff), commit it, then go back through the
  **approval gate** — the bump invalidated the prior approval, so the new revision
  must be re-approved before Implement resumes. Under Autopilot this **stops and
  returns to the human** (a new decision is required).

### 6. Finish
- Run the `verify.gate` once more.
- Write `.octospec/journal/<slug>.md` from `_journal.template.md`: a **one-line
  result** plus a `## Learning` section. Cross-reference the spec and PR rather
  than restating the Goal — the Learning is the journal's only unique value (it is
  the raw material for rules). Start it with OKF frontmatter (`type: Journal` +
  title/description/tags/timestamp). Do **not** maintain a per-task change log —
  the git history and the journal already carry the timeline and the detail.
- Promote any reusable learning **in this same PR**: edit the relevant
  `.octospec/rules/<rule>.md` in place (or add a new rule + `_index.yaml` entry) —
  the PR review is the gate. The helper `.octospec/scripts/octospec-update-spec.sh`
  gives you the raw material: `--kind=rule` → a draft at
  `.octospec/tasks/<slug>/<slug>-rule-draft.md` + a promotion block on stdout. It
  never auto-writes `rules/`, so **you** copy the draft into `rules/<id>.md` and
  update `_index.yaml` here, in this PR, then **delete the scratch draft**. If a
  learning surfaced but isn't ready to be a rule, keep it in the task journal's
  `## Learning` section — do not leave a rule draft behind.
- Open a PR. Because the branch already carries discovery + spec + approval, the
  PR contains the spec automatically. Fill the PR template's **Linked Spec** (→
  the spec, noting the approved revision) and the **COMPREHENSION** three
  questions to substance, for load-bearing / architectural / P0 changes.

## Autopilot

`/octospec autopilot <slug>` runs the mechanical tail of the loop unattended:
**Implement (Red→Green→Refactor) → Verify → (impl/test-only Iterate, ≤2 retries)
→ Finish (open PR)**. It exists because, once the spec is approved, no new
*human* decision arises until the PR itself — the middle phases are just "放行".

- **Precondition.** The spec's current `revision` must already be approved
  (autopilot never self-approves). If it is not, autopilot refuses and points the
  user at `/octospec approve <slug>`.
- **Red still comes first.** Even unattended, Implement commits the failing tests
  (`red: <slug>`) before production code — the git trail is what makes the later
  green trustworthy. This applies to **behavior-change** slices; a slice with only
  `N/A(test)` / `N/A(test-first)` acceptance items has no `red:` commit to require
  (see Slice classification), so the red-first check is conditional on there being
  at least one testable item.
- **Stops and returns to the human** on: a **spec-changing** Iterate (the
  revision bumps → the new spec needs re-approval), or **impl/test-only retries
  exhausted** (2 failed fix→verify cycles). Report what blocked it.
- **Never auto-merges.** It stops at "PR opened". The PR review is the second
  human gate, by design.
- Verify inside autopilot is still the **independent** pass (§4) — a fresh
  reviewer, not the implementing context.

## Notes

- `/octospec autopilot <slug>` runs Implement → Verify → Finish unattended after
  approval, stopping only when a human decision is needed (see **Autopilot**).
- `/octospec next <slug>` inspects task state (branch? discovery? spec? approved?
  diff? verify result?) and runs the next phase for you.
- `/octospec status <slug>` reports the current phase and what is blocking,
  read-only.
- The flow is guidance; the repo's PR/CI checks are the enforcement layer. The
  approval gate is enforced by Implement refusing an unapproved revision.
- **Spec filename (compat).** The task spec is `.octospec/tasks/<slug>/spec.md`
  (renamed from `brief.md` in 2.1.0). When reading an existing task, if `spec.md`
  is absent, fall back to a legacy `brief.md` for one release cycle so
  pre-2.1.0 tasks don't break; always **write** `spec.md`. New tasks only ever
  use `spec.md`.
