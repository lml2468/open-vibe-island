---
type: Task
title: "Task: <slug>"
description: <one-line summary of the task>
tags: []
timestamp: <ISO8601>
# --- octospec extension fields ---
slug: <slug>
upstream: <issue ref, e.g. repo#123>
source: self
# revision bumps ONLY on a spec-changing iteration (see Iteration Log). Each
# revision needs a matching approval below before Implement may run.
# `approvals:` is an empty block sequence — `/octospec approve` APPENDS a block
# item under it (do NOT write `approvals: []`; appending a block item under a
# flow-style empty list is invalid YAML and would break the machine-checkable gate).
revision: 1
approvals:
  # - revision: 1
  #   by: <git config user.name>
  #   at: <ISO8601 UTC>
---

# Task: <slug>

> One task = one `.octospec/tasks/<slug>/` directory. This `spec.md` is the spec
> for the work, derived from `discovery.md`. AI drafts it; a human **approves** it
> (via `/octospec approve <slug>`) before Implement may start.

## Goal
<!-- What behavior changes and why. -->

## Background
<!-- Context a reviewer needs. Links to issue, prior art, the discovery notes. -->

## Load-bearing list
<!-- Existing behaviors/contracts this change touches. Derive from discovery.md.
     Drives review depth and rule injection (touches: tags). Be honest and
     complete — an accurate list is what makes the right rules get injected. -->
- 

## Out of scope
<!-- What this change deliberately does NOT touch. -->
- 

## Slice class
<!-- Exactly one (see the octospec-workflow "Slice classification"):
     - behavior-change   — changes observable behavior; Acceptance = failing tests.
     - pure-relocation   — moves code, behavior unchanged; Verify = byte-equivalent
                           diff + suite stays green.
     - characterization  — pins CURRENT behavior so a later slice can refactor;
                           Verify = discriminating assertions.
     If a task spans two classes, split it. -->
class: <behavior-change | pure-relocation | characterization>

## Acceptance
<!-- Depends on the slice class:
     - behavior-change: each item is a FAILING test that Implement writes first
       (TDD Red) and commits before production code. State it machine-checkably:
       input, expected observable behavior, the assertion.
     - pure-relocation: mark `N/A(test): relocation` — criterion is a
       byte-equivalent behavior diff + the existing suite staying green.
     - characterization: mark `N/A(test-first): characterization` — criterion is
       discriminating assertions that would catch the next slice's regression.
     Silently skipping a test on a behavior-change item is not allowed. -->
- 

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec (load-bearing list,
     goal, scope, or acceptance). A spec-changing entry also bumps `revision`
     above and invalidates the prior approval — the new revision must be
     re-approved before Implement resumes. Impl-only fixes do NOT belong here
     (git already records those). Record the semantic reason, not the diff. -->
<!-- - r2 (Verify→Plan): <what the load-bearing list missed and why it changed> -->
