---
type: Journal
title: "Journal: <slug>"
description: <one-line result of the task>
tags: []
timestamp: <ISO8601>
# --- octospec extension fields ---
slug: <slug>
---

# Journal: <slug>

> The **Finish** phase output. Keep it thin: a one-line result plus the Learning.
> Do NOT restate the Goal or repeat the PR description — cross-reference the spec
> (`.octospec/tasks/<slug>/spec.md`) and the PR instead. The `## Learning`
> section is this file's only unique value: it is the raw material a reusable rule
> is promoted from. There is no per-task change log — git history carries the
> timeline.

**Result:** <one line — what shipped, linking the spec + PR.>

## Learning
<!-- What would you tell the next person touching this area? A gotcha, a contract
     that wasn't obvious, a rule this task should have had. If it should constrain
     EVERY future task, promote it to `.octospec/rules/` in this same PR (see the
     Finish phase / octospec-update-spec.sh). If nothing reusable came up, say so
     in one line and stop. -->
- 
