#!/usr/bin/env bash
# octospec-sync — vendor the pinned global ("constitution") rules into a
# git-ignored local cache, refresh the octospec-managed template surfaces, and
# materialize the repo-root scaffolding Claude Code discovers.
#
# Inheritance model: vendor snapshot + version pin (NOT git submodule).
#   - manifest.yaml declares `inherits: octo-spec@<semver>`
#   - this script fetches that version's global/ into .octospec/_global/
#   - _global/ is git-ignored; upgrading = bump the pin + re-run this script.
#
# What sync does, in order:
#   1) version-assert (manifest pin == GLOBAL_SRC VERSION), then vendor global/
#      into .octospec/_global/.
#   1b) refresh the octospec-MANAGED surfaces from the GLOBAL_SRC template
#      (.claude/, .github/, and the fill-in _spec/_discovery/_journal templates)
#      so an upgrade actually delivers the pinned version. User content
#      (manifest.yaml, tasks/, journal/, rules/) is never touched.
#   2) materialize repo-root scaffolding tools only discover at the root: copy
#      .octospec/.claude/ -> repo-root .claude/ (install-if-missing) and prune
#      octospec-managed root commands the template no longer ships.
#
# This is Claude-only: octospec is discovered via the Claude Code skill/command
# under .claude/. sync does NOT write CLAUDE.md/AGENTS.md/GEMINI.md/QWEN.md.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OCTOSPEC_DIR="$REPO_ROOT/.octospec"
MANIFEST="$OCTOSPEC_DIR/manifest.yaml"
GLOBAL_CACHE="$OCTOSPEC_DIR/_global"

[ -f "$MANIFEST" ] || { echo "no $MANIFEST"; exit 1; }

PIN="$(grep -E '^inherits:' "$MANIFEST" | sed -E 's/^inherits:[[:space:]]*//')"
echo "octospec: inherits = $PIN"

# GLOBAL_SRC: path to a checkout of octo-spec at the pinned version.
# Override via env: GLOBAL_SRC=/path/to/octo-spec ./octospec-sync.sh
GLOBAL_SRC="${GLOBAL_SRC:-}"
if [ -z "$GLOBAL_SRC" ]; then
  echo "set GLOBAL_SRC to a checkout of octo-spec (at version: $PIN)" >&2
  echo "  e.g. GLOBAL_SRC=/path/to/octo-spec ./.octospec/scripts/octospec-sync.sh" >&2
  exit 1
fi

# --- Version assertion: manifest pin must match the GLOBAL_SRC checkout. (YUJ-5344)
# Re-sync drift guard: bumping the pin without checking out the matching tag would
# silently vendor the wrong version's global rules. fail-fast like the GLOBAL_SRC
# unset path above. Escape hatch for deliberate cross-version debugging only.
if [ "${OCTOSPEC_SKIP_VERSION_CHECK:-0}" != "1" ]; then
  # Version = part after '@', tolerating a trailing inline comment / whitespace.
  PIN_VER="$(printf '%s' "${PIN##*@}" | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  SRC_VERSION_FILE="$GLOBAL_SRC/VERSION"
  if [ ! -f "$SRC_VERSION_FILE" ]; then
    echo "octospec: cannot verify version — no VERSION file at $SRC_VERSION_FILE" >&2
    echo "octospec: 无法校验版本 — $SRC_VERSION_FILE 不存在，GLOBAL_SRC 不像 octo-spec checkout，已中止。" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  SRC_VER="$(tr -d '[:space:]' < "$SRC_VERSION_FILE")"
  if [ -z "$SRC_VER" ]; then
    echo "octospec: cannot verify version — $SRC_VERSION_FILE is empty; aborting." >&2
    echo "octospec: 无法校验版本 — $SRC_VERSION_FILE 为空，已中止。" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  if [ "$PIN_VER" != "$SRC_VER" ]; then
    echo "octospec: VERSION MISMATCH — manifest pins octo-spec@$PIN_VER but GLOBAL_SRC checkout is $SRC_VER" >&2
    echo "octospec: 版本不一致 — manifest 钉 octo-spec@$PIN_VER，但 GLOBAL_SRC checkout 是 $SRC_VER" >&2
    echo "  Fix one of / 二选一修复:" >&2
    echo "    - check out octo-spec at the pinned tag:  git -C \"\$GLOBAL_SRC\" checkout v$PIN_VER" >&2
    echo "    - or change the manifest pin back to:     inherits: octo-spec@$SRC_VER" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  echo "octospec: version OK (pin $PIN_VER == checkout $SRC_VER)"
fi

# 1) Vendor the global rules.
rm -rf "$GLOBAL_CACHE"
mkdir -p "$GLOBAL_CACHE"
cp -r "$GLOBAL_SRC/global/." "$GLOBAL_CACHE/"
echo "octospec: synced global rules -> $GLOBAL_CACHE"

# 1b) Refresh the octospec-MANAGED template surfaces from GLOBAL_SRC — same
# freshness model as _global/ above. Without this, upgrading (bump the pin +
# re-run sync) would reconcile the repo root against a STALE vendored
# `.octospec/.claude`, so a deleted v1 command would never be pruned and a new
# router would never be installed (the exact upgrade gate-bypass reviewers hit).
# Only octospec-owned scaffolding is refreshed; USER content is never touched:
# manifest.yaml (the pin), tasks/<slug>/ (real tasks), journal/<slug>.md (real
# journals), and rules/*.md + rules/_index.yaml (the repo's own rules) are all
# left exactly as the user has them.
TEMPLATE_SRC="$GLOBAL_SRC/templates/octospec-init"
if [ -d "$TEMPLATE_SRC" ]; then
  # Whole managed subtrees (contain zero user content by design). We intentionally
  # do NOT refresh scripts/ here: this very script runs from .octospec/scripts/,
  # so rm-ing that dir mid-run would unlink the running file. scripts/ refresh
  # stays a documented manual step (re-copy the template on upgrade); the sync
  # regression test's drift guard keeps the copies honest.
  for sub in .claude .github; do
    if [ -d "$TEMPLATE_SRC/$sub" ]; then
      rm -rf "$OCTOSPEC_DIR/$sub"
      cp -r "$TEMPLATE_SRC/$sub" "$OCTOSPEC_DIR/$sub"
    fi
  done
  # Individual fill-in templates (never the user's real tasks/journals/rules).
  for f in tasks/_spec.template.md tasks/_discovery.template.md \
           journal/_journal.template.md; do
    if [ -f "$TEMPLATE_SRC/$f" ]; then
      mkdir -p "$OCTOSPEC_DIR/$(dirname "$f")"
      rm -f "$OCTOSPEC_DIR/$f"
      cp "$TEMPLATE_SRC/$f" "$OCTOSPEC_DIR/$f"
    fi
  done
  echo "octospec: refreshed managed template surfaces from $TEMPLATE_SRC"
else
  echo "octospec: WARNING no template at $TEMPLATE_SRC; skipping managed refresh" >&2
fi

# Ensure _global/ is git-ignored (with a trailing-newline guard so we never glue
# onto a previous line that lacks a newline).
GITIGNORE="$OCTOSPEC_DIR/.gitignore"
if ! grep -qxF "_global/" "$GITIGNORE" 2>/dev/null; then
  if [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ]; then
    printf '\n' >> "$GITIGNORE"
  fi
  printf '_global/\n' >> "$GITIGNORE"
fi

# 2) Materialize repo-root scaffolding that tools only discover at the root.
# The template tree carries .octospec/.claude/ (slash commands + skills) and
# .octospec/.github/PULL_REQUEST_TEMPLATE.md, but Claude Code only discovers
# slash commands/skills under the REPO ROOT .claude/, and GitHub only applies a
# PR template at the REPO ROOT .github/. So copy these out of .octospec/ to the
# root with TWO policies:
#   - octospec-OWNED files (commands/octospec*.md, skills/octospec-*/**, and the
#     PR template) are REFRESHED FROM SOURCE (overwritten) every run, so an
#     upgrade actually delivers the pinned version. These have stable paths, so
#     copy-if-absent would leave them frozen at the first-installed version — the
#     exact stale-root-skill gate-bypass reviewers hit.
#   - any OTHER file under .claude/ (a user's own command/skill) is
#     install-if-missing: an existing destination is left untouched so
#     hand-written customizations are never clobbered.
# Either way the step is idempotent.
#
# is_octospec_owned REL — true if the repo-relative .claude path is a file
# octospec manages (and may therefore overwrite on refresh).
is_octospec_owned() {
  case "$1" in
    commands/octospec*.md) return 0;;
    skills/octospec-*/*)   return 0;;
    *) return 1;;
  esac
}

# install_or_refresh SRC_DIR DEST_DIR LABEL — copy every file under SRC_DIR into
# DEST_DIR (mirroring subpaths). octospec-owned files overwrite; others are
# install-if-missing.
install_or_refresh() {
  src_dir="$1"; dest_dir="$2"; label="$3"
  [ -d "$src_dir" ] || return 0
  installed=0; refreshed=0; skipped=0
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    rel="${src#"$src_dir"/}"
    dest="$dest_dir/$rel"
    if is_octospec_owned "$rel"; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      refreshed=$((refreshed + 1))
    elif [ -e "$dest" ]; then
      skipped=$((skipped + 1))
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      installed=$((installed + 1))
    fi
  done <<EOF
$(find "$src_dir" -type f)
EOF
  echo "octospec: $label -> refreshed $refreshed, installed $installed, kept $skipped existing"
}

install_or_refresh "$OCTOSPEC_DIR/.claude" "$REPO_ROOT/.claude" ".claude (slash commands + skills)"

# 2b) Prune octospec-managed command files that no longer exist in the template.
# install_missing is copy-if-absent, so a command REMOVED from the template (e.g.
# the v1 octospec-{plan,go,check,finish} consolidated into one octospec.md) would
# otherwise linger at the repo root forever and keep offering a pre-gate flow that
# bypasses the approval gate. We reconcile-to-source, but ONLY within octospec's
# own namespace: files matching `octospec*.md` under .claude/commands/. A file the
# template still ships (octospec.md) is kept; a user's own non-octospec command is
# never touched. This is deletion, so it is deliberately scoped and namespaced.
prune_obsolete_commands() {
  src_cmd_dir="$OCTOSPEC_DIR/.claude/commands"
  dest_cmd_dir="$REPO_ROOT/.claude/commands"
  [ -d "$dest_cmd_dir" ] || return 0
  pruned=0
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    base="$(basename "$dest")"
    # Only ever consider octospec-managed command files.
    case "$base" in octospec*.md) :;; *) continue;; esac
    if [ ! -e "$src_cmd_dir/$base" ]; then
      rm -f "$dest"
      pruned=$((pruned + 1))
      echo "octospec: pruned obsolete command $base"
    fi
  done <<EOF
$(find "$dest_cmd_dir" -maxdepth 1 -type f -name 'octospec*.md' 2>/dev/null)
EOF
  echo "octospec: command prune -> removed $pruned obsolete"
}
prune_obsolete_commands

PRT_SRC="$OCTOSPEC_DIR/.github/PULL_REQUEST_TEMPLATE.md"
PRT_DEST="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
if [ -f "$PRT_SRC" ]; then
  # The PR template is octospec-managed: refresh it from source every run so an
  # upgrade delivers the current template (it has a stable path, so copy-if-absent
  # would freeze it at the first-installed version).
  mkdir -p "$REPO_ROOT/.github"
  cp "$PRT_SRC" "$PRT_DEST"
  echo "octospec: .github/PULL_REQUEST_TEMPLATE.md -> refreshed from source"
fi

echo "octospec: done."
