#!/usr/bin/env bash
# Self-test for octospec-update-spec.sh — exercises the --kind=rule reflow and
# asserts the products. Runs against a throwaway slug namespace (selftest-*) and
# cleans up the drafts it creates, so it never leaves the repo dirty.
# Exit 0 = all pass.
#
# The former --kind=task per-actor journal lane was removed in 2.1.0 (the Finish
# phase writes the flat .octospec/journal/<slug>.md directly), so this self-test
# covers the rule lane plus a guard that --kind=task is now refused.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/octospec-update-spec.sh"
# Run against an isolated throwaway .octospec/ fixture so the test never depends
# on (or pollutes) the directory the script ships in. The script honors the
# exported OCTOSPEC_DIR; the fixture's parent acts as the repo root.
FIXTURE_ROOT="$(mktemp -d)"
export OCTOSPEC_DIR="$FIXTURE_ROOT/.octospec"
mkdir -p "$OCTOSPEC_DIR/tasks" "$OCTOSPEC_DIR/journal" "$OCTOSPEC_DIR/rules"
TASKS="$OCTOSPEC_DIR/tasks"
# The rule draft lives beside the task's spec under tasks/<slug>/.
draft_path() { printf '%s/%s/%s-rule-draft.md' "$TASKS" "$1" "$1"; }

pass=0
fail=0

# check <description> -- runs the rest of the args as a command; pass iff it
# exits 0. Keeps assertions free of `A && B || C` foot-guns (no SC2015).
check() {
  local desc="$1"; shift
  if "$@"; then
    echo "  ok: $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL: $desc" >&2
    fail=$((fail + 1))
  fi
}
contains() { printf '%s' "$2" | grep -qF -- "$1"; }
# refuses: succeeds iff the script exits non-zero for the given args.
refuses()  { ! "$SCRIPT" "$@" >/dev/null 2>&1; }
# refuses_stdin: like refuses but feeds empty stdin (for the no-learning case).
refuses_stdin() { ! "$SCRIPT" "$@" </dev/null >/dev/null 2>&1; }

cleanup() {
  rm -rf "$TASKS"/selftest-* "$TASKS"/ok-slug 2>/dev/null || true
}
# Single EXIT trap: scrub the test artifacts AND drop the throwaway fixture root,
# so repeated local runs never leak temp dirs.
on_exit() { cleanup; rm -rf "$FIXTURE_ROOT"; }
trap on_exit EXIT
cleanup

echo "== 1. --kind=rule (draft + promotion material) =="
BODY="$("$SCRIPT" --slug selftest-rule --kind rule --load-bearing \
  --inject-touches "space,audit" --priority 88 \
  --learning $'Cross-Space writes must record an audit entry.\nUse audit.Record before returning.')"
DRAFT="$(draft_path selftest-rule)"
check "draft file created" test -f "$DRAFT"
check "OKF type: Rule" grep -qx 'type: Rule' "$DRAFT"
for f in title description tags timestamp id tier priority load_bearing inject_when source; do
  check "frontmatter has $f" grep -qE "^(  )?${f}:" "$DRAFT"
done
check "--load-bearing -> true" grep -q 'load_bearing: true' "$DRAFT"
check "--priority honored" grep -q 'priority: 88' "$DRAFT"
check "inject touches present" grep -q '"audit"' "$DRAFT"
check "marked draft" grep -q 'status: draft' "$DRAFT"
check "promotion block has COMPREHENSION" contains 'COMPREHENSION' "$BODY"
nq="$(printf '%s\n' "$BODY" | grep -cE '^[0-9]+\. \*\*')"
check "promotion block has >=3 questions ($nq)" test "$nq" -ge 3
check "promotion block Linked task" contains 'Linked task' "$BODY"
check "promotion block links draft" contains 'selftest-rule-rule-draft.md' "$BODY"

echo "== 2. idempotency (rerun must not duplicate) =="
"$SCRIPT" --slug selftest-rule --kind rule --learning 'second run overwrites' --no-promote >/dev/null
n_after="$(find "$TASKS/selftest-rule" -maxdepth 1 -name 'selftest-rule-rule-draft.md' | wc -l | tr -d ' ')"
check "still exactly one draft after rerun" test "$n_after" -eq 1
check "default overwrites content" grep -q 'second run overwrites' "$DRAFT"
"$SCRIPT" --slug selftest-rule --kind rule --learning 'THIRD run skipped' --skip-existing --no-promote >/dev/null
check "--skip-existing preserves prior draft" grep -q 'second run overwrites' "$DRAFT"

echo "== 3. --kind=task is refused (removed in 2.1.0) =="
check "task kind refused" refuses --slug selftest-task --kind task --learning x
# The refusal names the flat-journal replacement so the caller knows where to go.
TASK_ERR="$("$SCRIPT" --slug selftest-task --kind task --learning x 2>&1 || true)"
check "task refusal points at flat journal" contains 'journal/<slug>.md' "$TASK_ERR"
check "task kind wrote NOTHING (no draft)" test ! -e "$(draft_path selftest-task)"
check "no by-actor tree materialized" test ! -d "$OCTOSPEC_DIR/journal/by-actor"

echo "== 4. input validation / refusals =="
check "missing --kind refused" refuses --slug ok-slug --learning x
check "bad --kind refused" refuses --slug ok-slug --kind bogus --learning x
check "bad slug refused" refuses --slug Bad_Slug --kind rule --learning x
check "empty learning refused" refuses_stdin --slug ok-slug --kind rule
# A value-taking option must not silently swallow the NEXT option as its value.
check "flag-as-value (--title --priority) refused" \
  refuses --title --priority 88 --slug ok-slug --kind rule --learning x
check "flag-as-value (--learning --kind) refused" \
  refuses --slug ok-slug --kind rule --learning --kind
# ...but the --opt=val escape hatch still accepts a value that starts with --.
check "--opt=--value escape hatch accepted" \
  "$SCRIPT" --slug ok-slug --kind rule --title=--weird --learning x --no-promote
rm -rf "$TASKS/ok-slug"

echo "== 5. backslash in learning -> valid YAML frontmatter (octospec-lint) =="
# A learning whose first line carries a regex (\d) and a Windows path (C:\tmp):
# the default description copies that line into a double-quoted YAML scalar, so a
# backslash that is not doubled produces malformed YAML and fails octospec-lint.
BS_LEARNING=$'Match \\d+ digits and the path C:\\tmp\\report before returning.\nKeep the backslashes intact.'

# Locate the linter if it ships alongside the consuming repo's scripts; else fall
# back to a self-contained YAML parse (the exact check octospec-lint performs).
LINT=""
for cand in "$HERE/octospec-lint.py" "$HERE/../../../scripts/octospec-lint.py"; do
  [ -f "$cand" ] && { LINT="$cand"; break; }
done

# yaml_ok <file>: succeeds iff the file's --- frontmatter --- block parses as YAML.
yaml_ok() {
  python3 - "$1" <<'PY'
import sys, yaml
text = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
lines = text.split("\n")
if not lines or lines[0].strip() != "---":
    sys.exit("no frontmatter")
close = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
if close is None:
    sys.exit("unterminated frontmatter")
data = yaml.safe_load("\n".join(lines[1:close]))
sys.exit(0 if isinstance(data, dict) and data.get("type") else "bad frontmatter")
PY
}

# rule path: draft frontmatter must be valid YAML despite the backslashes.
"$SCRIPT" --slug selftest-bs --kind rule --no-promote \
  --title 'Regex \d guard' --learning "$BS_LEARNING" >/dev/null
BS_DRAFT="$(draft_path selftest-bs)"
check "backslash rule draft created" test -f "$BS_DRAFT"
check "backslash rule draft is valid YAML frontmatter" yaml_ok "$BS_DRAFT"
check "backslash preserved in draft body" grep -qF 'C:\tmp\report' "$BS_DRAFT"
if [ -n "$LINT" ]; then
  # tasks/<slug>/ IS in octospec-lint scope; the backslash draft must pass.
  check "octospec-lint passes the backslash draft" \
    python3 "$LINT" "$OCTOSPEC_DIR"
else
  echo "  note: octospec-lint.py not found alongside scripts; used self-contained YAML parse"
fi
rm -f "$BS_DRAFT"

echo "== 6. literal newline in --title/--description folds to single-line YAML =="
"$SCRIPT" --slug selftest-nl --kind rule --no-promote \
  --title "$(printf 'line one\nline two')" \
  --description "$(printf 'desc a\ndesc b')" --learning 'body' >/dev/null
NL_DRAFT="$(draft_path selftest-nl)"
check "newline-title draft created" test -f "$NL_DRAFT"
check "newline-title draft is valid YAML frontmatter" yaml_ok "$NL_DRAFT"
check "title folded to one line" grep -q '^title: "line one line two"$' "$NL_DRAFT"
check "description folded to one line" grep -q '^description: "desc a desc b"$' "$NL_DRAFT"
rm -f "$NL_DRAFT"

echo "== 7. --rule-id must be kebab-case (no YAML-breaking chars) =="
check "rule-id with ':' refused" refuses --slug ok-slug --kind rule --rule-id 'bad:id' --learning x
check "rule-id with '/' refused"  refuses --slug ok-slug --kind rule --rule-id 'a/b' --learning x
check "rule-id starting non-letter refused" refuses --slug ok-slug --kind rule --rule-id '1abc' --learning x
# a clean kebab-case rule-id is accepted and lands as the id: scalar.
"$SCRIPT" --slug selftest-rid --kind rule --no-promote --rule-id 'custom-rule-id' \
  --learning 'rid body' >/dev/null
RID_DRAFT="$(draft_path selftest-rid)"
check "valid --rule-id accepted" test -f "$RID_DRAFT"
check "valid --rule-id written as id: scalar" grep -q '^id: custom-rule-id$' "$RID_DRAFT"
rm -f "$RID_DRAFT"

echo
echo "RESULT: $pass passed, $fail failed"
test "$fail" -eq 0
