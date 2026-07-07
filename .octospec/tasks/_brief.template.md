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
revision: 1
approvals: []
  # - revision: 1
  #   by: <git config user.name>
  #   at: <ISO8601 UTC>
---

# Task: <slug>

> One task = one `.octospec/tasks/<slug>/` directory. This brief is the spec for
> the work, derived from `discovery.md`. AI drafts it; a human **approves** it
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

## Acceptance
<!-- Machine-checkable where possible: tests, assertions, repro that must pass. -->
- 

## Iteration Log
<!-- Add an entry ONLY when an iteration changes the spec (load-bearing list,
     goal, scope, or acceptance). A spec-changing entry also bumps `revision`
     above and invalidates the prior approval — the new revision must be
     re-approved before Implement resumes. Impl-only fixes do NOT belong here
     (git already records those). Record the semantic reason, not the diff. -->
<!-- - r2 (Verify→Plan): <what the load-bearing list missed and why it changed> -->
