<!-- octospec:begin -->
## octo-spec engineering standard

This repo carries a shared engineering standard in `.octospec/`, readable by any
coding agent working in this checkout (Claude Code, Codex, OpenClaw, Gemini, or
others). **Follow it for any non-trivial change.**

When you take on a coding task here:

1. **Discover.** Read the code the task touches (read-only) and capture what you
   found in `.octospec/tasks/<slug>/discovery.md`. This grounds the load-bearing
   list so the right rules get injected.
2. **Plan → brief.** Derive `.octospec/tasks/<slug>/brief.md` from discovery:
   goal / load-bearing list / out-of-scope / acceptance
   (template: `.octospec/tasks/_brief.template.md`). A human **approves** the
   brief (records an approval for its `revision`) before you implement.
3. **Inject the rules that apply.** Read `.octospec/rules/` (index:
   `.octospec/rules/_index.yaml`) plus the inherited global rules in
   `.octospec/_global/`. A rule applies when its `inject_when.paths` matches a
   file you will touch, OR its `inject_when.touches` tag is in the brief's
   load-bearing list. **Read and follow the full text** of each matching rule
   before writing code; prioritize `load_bearing: true` rules.
4. **Implement** following those rules — only after the current brief revision is
   approved.
5. **Verify** the diff against each injected rule and the brief's acceptance; run
   the repo's gate (`manifest.yaml` `verify.gate`, else CLAUDE.md gates). Rework
   via **Iterate** if it fails (spec-changing rework re-triggers approval).
6. **Finish:** journal the work, land any reusable learning in this same PR, and
   open a PR filling **Linked Spec** + the **COMPREHENSION** three questions for
   load-bearing / architectural / P0 changes. Trivial changes
   (typo/docs/lint/config) are exempt.

Claude Code users drive this with one command: `/octospec <phase> <slug>`
(`discover|plan|implement|verify|iterate|finish`, plus `approve`, `next`,
`status`) — committed under `.claude/commands/`. Other agents read the same
`.octospec/` files directly — the steps above are the same regardless of tool.

The first time you apply this in a session, tell the user in one line that this
repo follows the octo-spec standard and point them at `.octospec/` (and
`docs/` in the octo-spec repo) for detail.

This region is managed by octospec-sync; edit outside the markers.
<!-- octospec:end -->
