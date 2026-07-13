#!/usr/bin/env bash
# octospec-update-spec — Finish-phase learning reflow tool.
#
# Turns a single task's reusable learning into a rule DRAFT + promotion material.
# The script never auto-writes main's rules/ — that safety floor keeps the
# comprehension gate human — but it produces the material the author uses to land
# the rule IN THE SAME PR. This is the executable backing for the parity design §3
# (learning reflow).
#
# One reflow path (`--kind=rule`):
#
#   --kind=rule  (規範級 / rule-level)
#     A learning that should constrain EVERY future task. The script:
#       1. writes a DRAFT OKF Rule (full frontmatter + octospec extension fields)
#          to  .octospec/tasks/<slug>/<slug>-rule-draft.md
#          — scratch material for THIS PR (lives beside the task's spec/discovery,
#            deleted once the rule lands), not a dead-letter to promote later;
#       2. prints promotion material to stdout (proposed rule body + COMPREHENSION
#          three questions + a checklist) so the AUTHOR can, in this same PR,
#          land the rule into .octospec/rules/<id>.md and add the
#          rules/_index.yaml entry. The PR review is the comprehension gate.
#     The script writes the draft + material; the author (a human, in this PR)
#     does the rules/ landing. The script itself never edits rules/ or
#     rules/_index.yaml — that is the only step it leaves to the author, and it
#     happens in the same PR, never a separate one.
#
#   Task-level journals are NOT written by this helper. The Finish phase writes
#   the task journal directly to the flat `.octospec/journal/<slug>.md` (one-line
#   Result + `## Learning`) from `_journal.template.md`. The former `--kind=task`
#   per-actor `journal/by-actor/` lane was removed in 2.1.0 (flat single journal).
#
# Idempotency: rerunning the same slug does not pile up files. By default the rule
# draft is OVERWRITTEN in place; with --skip-existing an existing file is left
# untouched.
#
# No hard external dependencies. Style mirrors octospec-sync.sh (set -euo
# pipefail, atomic writes, explicit refusals).
#
# Usage:
#   octospec-update-spec.sh --slug <slug> --kind rule [--learning <text>] [opts]
#   echo "<learning text>" | octospec-update-spec.sh --slug <slug> --kind rule
#
# Common options:
#   --slug <slug>            (required) kebab-case task slug.
#   --kind rule              (required) reflow path (only `rule` is supported).
#   --learning <text>        Learning text. If omitted, read from stdin.
#   --skip-existing          do not overwrite an existing draft.
#   --no-promote             write the draft but suppress the promotion material
#                            on stdout (escape hatch to avoid noise).
#
# Rule options (sane defaults; the human refines in review):
#   --title <title>          Rule title (default: derived from slug).
#   --description <text>     Rule description (default: first line of learning).
#   --tags <a,b,c>           OKF tags (default: from --inject-touches or slug).
#   --rule-id <id>           Rule id (default: <slug>).
#   --tier repo|global       (default: repo).
#   --priority <0-100>       (default: 50).
#   --load-bearing           Mark load_bearing: true (default: false).
#   --inject-paths <g,...>   inject_when.paths globs (default: ["**"]).
#   --inject-touches <t,...> inject_when.touches tags (default: []).
#
# Exit codes: 0 ok; 2 = usage error / refusal.
set -euo pipefail

PROG="octospec-update-spec"

die() { echo "$PROG: $*" >&2; exit 2; }

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^#$//'
}

# --- locate the .octospec dir (works from anywhere inside the repo) -----------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Respect an explicitly provided OCTOSPEC_DIR (the script ships as a template and
# is invoked against a target repo's .octospec/, which is NOT the script's own
# parent once installed). Fall back to scripts/.. only when unset.
OCTOSPEC_DIR="${OCTOSPEC_DIR:-$(cd "$HERE/.." && pwd)}"   # scripts/ -> .octospec/

# --- defaults -----------------------------------------------------------------
SLUG=""
KIND=""
LEARNING=""
LEARNING_SET=0
SKIP_EXISTING=0
NO_PROMOTE=0
TITLE=""
DESCRIPTION=""
TAGS=""
RULE_ID=""
TIER="repo"
PRIORITY="50"
LOAD_BEARING="false"
INJECT_PATHS=""
INJECT_TOUCHES=""

# --- arg parsing (supports `--opt val` and `--opt=val`) -----------------------
while [ $# -gt 0 ]; do
  arg="$1"
  val=""
  case "$arg" in
    --*=*) val="${arg#*=}"; arg="${arg%%=*}";;
  esac
  takeval() {
    if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
    [ $# -ge 2 ] || die "option $1 needs a value"
    # Reject the next token when it is itself a long option (--foo): otherwise a
    # mistyped `--title --priority 88` silently swallows `--priority` as the
    # title. The `--opt=val` form sets $val above and never reaches here, so
    # values that legitimately start with a single dash still work via `--opt=-x`.
    case "$2" in
      --*) die "option $1 needs a value (got the option '$2'); use $1=<value> if the value really starts with --";;
    esac
    printf '%s' "$2"
  }
  case "$arg" in
    -h|--help) usage; exit 0;;
    --slug)          SLUG="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --kind)          KIND="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --learning)      LEARNING="$(takeval "$@")"; LEARNING_SET=1; [ -n "$val" ] || shift;;
    --title)         TITLE="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --description)   DESCRIPTION="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --tags)          TAGS="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --rule-id)       RULE_ID="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --tier)          TIER="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --priority)      PRIORITY="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --inject-paths)  INJECT_PATHS="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --inject-touches) INJECT_TOUCHES="$(takeval "$@")"; [ -n "$val" ] || shift;;
    --load-bearing)  LOAD_BEARING="true";;
    --skip-existing) SKIP_EXISTING=1;;
    --no-promote)    NO_PROMOTE=1;;
    --) shift; break;;
    -*) die "unknown option: $arg (use --help)";;
    *) die "unexpected argument: $arg";;
  esac
  shift
done

# --- validate -----------------------------------------------------------------
[ -n "$SLUG" ] || die "--slug is required"
[ -n "$KIND" ] || die "--kind is required (rule)"
case "$KIND" in
  rule) :;;
  task) die "--kind=task was removed in 2.1.0; the Finish phase writes the flat journal/<slug>.md directly (see octospec-workflow SKILL §6)";;
  *) die "--kind must be 'rule', got: $KIND";;
esac
case "$SLUG" in
  [a-z]*) :;;
  *) die "--slug must be kebab-case, start with a letter: $SLUG";;
esac
case "$SLUG" in
  *[!a-z0-9-]*) die "--slug must match [a-z0-9-]: $SLUG";;
esac
case "$PRIORITY" in
  ''|*[!0-9]*) die "--priority must be an integer 0-100: $PRIORITY";;
  *) [ "$PRIORITY" -le 100 ] || die "--priority must be 0-100: $PRIORITY";;
esac
case "$TIER" in repo|global) :;; *) die "--tier must be repo|global: $TIER";; esac

# title/description land in a single-line double-quoted YAML scalar; a literal
# newline would split the scalar and emit malformed YAML. Fold embedded newlines
# (and carriage returns) to spaces so a multi-line value stays lint-clean.
TITLE="$(printf '%s' "$TITLE" | tr '\n\r' '  ')"
DESCRIPTION="$(printf '%s' "$DESCRIPTION" | tr '\n\r' '  ')"

# --- gather the learning text -------------------------------------------------
if [ "$LEARNING_SET" -eq 0 ]; then
  if [ -t 0 ]; then
    die "no learning text: pass --learning <text> or pipe it on stdin"
  fi
  LEARNING="$(cat)"
fi
# Trim leading/trailing blank lines but keep internal structure.
# Portable (awk, no GNU-sed extensions): buffer the lines, drop leading and
# trailing empty lines, print the rest verbatim. Works on BSD/macOS + Linux.
LEARNING="$(printf '%s\n' "$LEARNING" | awk '
  { line[NR] = $0 }
  END {
    s = 1;  while (s <= NR && line[s] == "") s++
    e = NR; while (e >= s  && line[e] == "") e--
    for (i = s; i <= e; i++) print line[i]
  }')"
[ -n "$LEARNING" ] || die "learning text is empty"

FIRST_LINE="$(printf '%s\n' "$LEARNING" | sed -n '1p')"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- helpers: slug -> Title Case; comma list -> YAML flow seq ------------------
titlecase_slug() {
  printf '%s' "$1" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}; print}'
}

# Turn "a, b ,c" into a YAML/JSON-safe flow sequence: ["a","b","c"].
# Empty input yields []. Pathname expansion is disabled around the unquoted
# split so glob-like items (e.g. "modules/**/*.go") stay literal.
csv_to_flow_seq() {
  local csv="$1" out="" item first=1
  local IFS=','
  local restore_glob=1
  case "$-" in *f*) restore_glob=0;; esac
  set -f
  # shellcheck disable=SC2086  # intentional word-split on IFS=',' with glob off
  for item in $csv; do
    # trim surrounding whitespace
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] || continue
    # escape backslash and double-quote for safe quoting
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    if [ "$first" -eq 1 ]; then out="\"$item\""; first=0; else out="$out, \"$item\""; fi
  done
  [ "$restore_glob" -eq 1 ] && set +f
  printf '[%s]' "$out"
}

# Atomic write: temp file in target dir + mv (mirrors octospec-sync.sh).
atomic_write() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  tmp="$dir/.$(basename "$target").$PROG.tmp"
  printf '%s' "$content" > "$tmp"
  mv -f "$tmp" "$target"
}

# ============================================================================
# kind=rule
# ============================================================================
if [ "$KIND" = "rule" ]; then
  [ -n "$RULE_ID" ] || RULE_ID="$SLUG"
  # RULE_ID becomes the YAML `id:` scalar and the rules/<id>.md filename, so hold
  # it to the same kebab-case shape as --slug. A raw value with `:` or `/` would
  # emit malformed frontmatter / a bad path; reject it rather than escape it.
  case "$RULE_ID" in
    [a-z]*) :;;
    *) die "--rule-id must be kebab-case, start with a letter: $RULE_ID";;
  esac
  case "$RULE_ID" in
    *[!a-z0-9-]*) die "--rule-id must match [a-z0-9-]: $RULE_ID";;
  esac
  if [ -z "$TITLE" ]; then TITLE="$(titlecase_slug "$SLUG")"; fi
  if [ -z "$DESCRIPTION" ]; then DESCRIPTION="$FIRST_LINE"; fi

  # tags default: inject-touches, else the slug.
  if [ -z "$TAGS" ]; then
    if [ -n "$INJECT_TOUCHES" ]; then TAGS="$INJECT_TOUCHES"; else TAGS="$SLUG"; fi
  fi
  TAGS_SEQ="$(csv_to_flow_seq "$TAGS")"
  TOUCHES_SEQ="$(csv_to_flow_seq "$INJECT_TOUCHES")"
  if [ -n "$INJECT_PATHS" ]; then
    PATHS_SEQ="$(csv_to_flow_seq "$INJECT_PATHS")"
  else
    PATHS_SEQ='["**"]'
  fi

  # The rule draft is scratch material for THIS PR: it lives alongside the task's
  # spec/discovery under tasks/<slug>/, so it rides the task branch, is visible in
  # review, and is deleted once the author lands the rule into rules/. (There is no
  # separate learnings/pending/ dead-letter — a finished rule goes to rules/, an
  # unfinished idea goes in the task journal's ## Learning.)
  DRAFT_DIR="$OCTOSPEC_DIR/tasks/$SLUG"
  DRAFT_PATH="$DRAFT_DIR/${SLUG}-rule-draft.md"
  mkdir -p "$DRAFT_DIR"

  if [ -e "$DRAFT_PATH" ] && [ "$SKIP_EXISTING" -eq 1 ]; then
    echo "$PROG: draft exists, --skip-existing set; leaving $DRAFT_PATH untouched" >&2
  else
    # YAML-escape the title/description for a double-quoted scalar: escape
    # backslash FIRST, then the double-quote (order matters). A double-quoted
    # YAML scalar treats both \ and " specially, so input like a regex (\d) or a
    # Windows path (C:\tmp) must have its backslashes doubled or octospec-lint
    # rejects the frontmatter as malformed YAML.
    y_title="${TITLE//\\/\\\\}"; y_title="${y_title//\"/\\\"}"
    y_desc="${DESCRIPTION//\\/\\\\}"; y_desc="${y_desc//\"/\\\"}"
    DRAFT_CONTENT="$(cat <<EOF
---
type: Rule
title: "$y_title"
description: "$y_desc"
tags: $TAGS_SEQ
timestamp: $TIMESTAMP
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
# DRAFT — generated by $PROG for slug "$SLUG". Scratch material for THIS PR.
# The author lands it into rules/<id>.md + rules/_index.yaml in this same PR;
# the PR review is the comprehension gate. The script never auto-writes rules/.
id: $RULE_ID
tier: $TIER
priority: $PRIORITY
load_bearing: $LOAD_BEARING
inject_when:
  paths: $PATHS_SEQ
  touches: $TOUCHES_SEQ
source: self
supersedes: []
status: draft
draft_source_slug: $SLUG
---

# $TITLE

$LEARNING

## Why load-bearing
<!-- Reviewer: state why every future task must obey this. If it does NOT bind
     every future task, don't promote it to a rule — record it in the task's own
     journal (.octospec/journal/<slug>.md, the `## Learning` section) instead. -->
EOF
)"
    atomic_write "$DRAFT_PATH" "$DRAFT_CONTENT
"
    echo "$PROG: wrote rule draft -> $DRAFT_PATH" >&2
  fi

  # Promotion material -> stdout (unless suppressed).
  if [ "$NO_PROMOTE" -eq 1 ]; then
    echo "$PROG: --no-promote set; skipping promotion material" >&2
    exit 0
  fi

  REL_DRAFT=".octospec/tasks/${SLUG}/${SLUG}-rule-draft.md"
  REL_SPEC=".octospec/tasks/${SLUG}/spec.md"
  cat <<EOF
## Rule reflow: $TITLE

**Linked task:** \`$REL_SPEC\` (slug: \`$SLUG\`)
**Proposed rule:** id \`$RULE_ID\`, tier \`$TIER\`, priority \`$PRIORITY\`, load_bearing \`$LOAD_BEARING\`
**Draft (scratch material for this PR):** \`$REL_DRAFT\`

> Generated by \`$PROG\`. Use this material to land the rule IN THIS SAME PR:
> copy the draft into \`.octospec/rules/$RULE_ID.md\` and add the
> \`rules/_index.yaml\` entry. The PR review is the comprehension gate; the
> script does not auto-write rules/. Do NOT defer this to a separate PR.

### Proposed rule body
$LEARNING

### COMPREHENSION (answer to substance before merge)
1. **What does this rule actually constrain** on the load-bearing path? Describe
   the behavior every future task must follow, not the file list.
2. **What could break / be over-constrained** if this rule is injected widely?
   Name the dependents and the failure mode.
3. **How do we know it's right** — what evidence (the originating task, a repro,
   a trace) shows this should bind all future work rather than stay a heuristic?

### Author checklist (do these in this PR)
- [ ] inject_when (paths/touches) scopes the rule to where it actually applies.
- [ ] load_bearing/priority/tier are justified.
- [ ] Belongs in rules/ (binds everyone) vs the task journal (.octospec/journal/<slug>.md, one task's note).
- [ ] Land the rule now: copy draft into \`.octospec/rules/$RULE_ID.md\`, add the
      \`rules/_index.yaml\` entry, drop the draft.
EOF
  exit 0
fi

