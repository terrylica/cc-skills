#!/usr/bin/env bash
# site.sh — publish a static HTML directory to bigblack via Tailscale.
# Modeled on scripts/blob.sh from opendeviationbar-patterns. Adapt freely
# into other repos: copy this file, copy .mise/tasks/site.toml, copy
# scripts/check-orphan-pages.py, and you're done.
#
# Subcommands:
#   nav <local-dir>         Regenerate site-map.html + auto-nav rail (no network)
#   push <local-dir>        Build nav + validate + rsync to bigblack:~/sites/<project>/<page>/
#   check <local-dir>       Build nav + validate only (lychee + orphan-page detector)
#   url <local-dir>         Print the URL where <local-dir> would publish to
#   list                    List all published projects/pages on bigblack
#   unpublish <local-dir>   Remove the page from bigblack (asks for confirmation)
#
# URL format:
#   https://bigblack.tail0f299b.ts.net:8448/<project>/<page>/
#     <project>  derived from `git remote get-url origin` basename (or
#                $SITE_PROJECT_NAME override)
#     <page>     basename of <local-dir>
#
# Gate: every push runs lychee + orphan-page check FIRST. If either fails,
# nothing reaches bigblack. The validation is the only gate — there is no
# semantic-release here. Push-side gating, by design.

set -euo pipefail

# Repo detection: prefer git toplevel; fall back to PWD so site.sh works
# in non-git directories too (e.g. a one-off site assembled in /tmp).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BIGBLACK_SSH="${SITE_BIGBLACK_SSH:-bigblack}"
BIGBLACK_ROOT="${SITE_BIGBLACK_ROOT:-/home/tca/sites}"
SERVER_BASE_URL="${SITE_BASE_URL:-https://bigblack.tail0f299b.ts.net:8448}"

# Project namespace: from env or git remote
project_name() {
  if [[ -n "${SITE_PROJECT_NAME:-}" ]]; then
    echo "$SITE_PROJECT_NAME"
    return
  fi
  local remote
  remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote" ]]; then
    basename "$REPO_ROOT"
    return
  fi
  basename "$remote" .git
}

# Page namespace: basename of local dir
page_name() {
  local local_dir="$1"
  basename "$(cd "$local_dir" && pwd)"
}

# Resolve the URL where a local dir publishes to
build_url() {
  local local_dir="$1"
  local project page
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  echo "$SERVER_BASE_URL/$project/$page/"
}

# Resolve the bigblack remote path
build_remote_path() {
  local local_dir="$1"
  local project page
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  echo "$BIGBLACK_ROOT/$project/$page"
}

# require <command> [install-hint]
# Aborts with a friendly error + brew/install hint when the command is missing.
require() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✗ missing: $cmd" >&2
    [[ -n "$hint" ]] && echo "  Install: $hint" >&2
    exit 1
  fi
}

# Resolve build-nav.py: prefer scripts/build-nav.py in the consuming repo;
# fall back to the canonical copy that ships with this skill so a repo can
# call site.sh before it has copied the script in. Resolution order:
#   1. <repo>/scripts/build-nav.py
#   2. $CLAUDE_PLUGIN_ROOT/skills/page-template/scripts/build-nav.py
#      (set automatically by Claude Code when the skill is invoked)
#   3. Canonical install path: ~/.claude/plugins/marketplaces/cc-skills/...
resolve_build_nav() {
  if [[ -f "$REPO_ROOT/scripts/build-nav.py" ]]; then
    echo "$REPO_ROOT/scripts/build-nav.py"
    return
  fi
  local candidate
  for candidate in \
    "${CLAUDE_PLUGIN_ROOT:-}/skills/page-template/scripts/build-nav.py" \
    "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase/skills/page-template/scripts/build-nav.py"
  do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
  echo ""
}

cmd_nav() {
  local local_dir="${1:?nav <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  local build_nav
  build_nav="$(resolve_build_nav)"
  if [[ -z "$build_nav" ]]; then
    echo "✗ build-nav.py not found in $REPO_ROOT/scripts/ or the html-showcase plugin" >&2
    echo "  Copy it: cp \$CLAUDE_PLUGIN_ROOT/skills/page-template/scripts/build-nav.py ./scripts/" >&2
    exit 1
  fi
  echo "→ regenerating site-map + auto-nav for $local_dir"
  python3 "$build_nav" --root "$local_dir"
}

cmd_check() {
  local local_dir="${1:?check <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }

  # Always regenerate nav before validating — sitemap is the SSoT for the
  # page graph, and lychee/orphan-check both depend on it being fresh.
  cmd_nav "$local_dir"

  echo "→ validating $local_dir"

  # Lychee link check
  require lychee "brew install lychee  (or: cargo install lychee)"
  local lychee_config="$local_dir/lychee.toml"
  if [[ -f "$lychee_config" ]]; then
    echo "  lychee (config: $lychee_config)"
    lychee --config "$lychee_config" "$local_dir"/**/*.html 2>&1 | tail -20
  else
    echo "  lychee (no config; using defaults)"
    lychee "$local_dir"/**/*.html 2>&1 | tail -20
  fi
  local lychee_status=${PIPESTATUS[0]}
  if [[ $lychee_status -ne 0 ]]; then
    echo "✗ lychee found broken links — aborting" >&2
    exit 1
  fi

  # Orphan page detector
  if [[ -f "$REPO_ROOT/scripts/check-orphan-pages.py" ]]; then
    echo "  orphan-page check"
    python3 "$REPO_ROOT/scripts/check-orphan-pages.py" "$local_dir"
  else
    echo "  (skipped: scripts/check-orphan-pages.py not found)"
  fi

  echo "✓ validation passed"
}

cmd_push() {
  local local_dir="${1:?push <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }

  # 1. Validate first — push-side gate
  cmd_check "$local_dir"

  # 2. Stamp provenance
  local commit_sha timestamp project page url remote_path
  commit_sha="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  local dirty=""
  if ! git -C "$REPO_ROOT" diff --quiet -- "$local_dir" 2>/dev/null; then
    dirty="-dirty"
  fi
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  url="$(build_url "$local_dir")"
  remote_path="$(build_remote_path "$local_dir")"

  cat > "$local_dir/.published.json" <<JSON
{
  "project": "$project",
  "page": "$page",
  "commit": "${commit_sha}${dirty}",
  "published_utc": "$timestamp",
  "source_repo": "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo unknown)",
  "url": "$url"
}
JSON

  # 3. Rsync to bigblack
  echo "→ rsync $local_dir/ → $BIGBLACK_SSH:$remote_path/"
  # shellcheck disable=SC2029  # intentional client-side expansion of $remote_path
  ssh "$BIGBLACK_SSH" "mkdir -p '$remote_path'"
  rsync -av --delete \
    --exclude '.git/' \
    --exclude '.DS_Store' \
    --exclude '*.swp' \
    --exclude 'node_modules/' \
    --exclude '__pycache__/' \
    --exclude '.venv/' \
    "$local_dir/" "$BIGBLACK_SSH:$remote_path/"

  echo ""
  echo "✓ published"
  echo "  URL:    $url"
  echo "  Path:   $BIGBLACK_SSH:$remote_path"
  echo "  Commit: ${commit_sha}${dirty}"
}

cmd_url() {
  local local_dir="${1:?url <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  build_url "$local_dir"
}

cmd_list() {
  echo "=== $SERVER_BASE_URL ==="
  # Single SSH call: print "<project>/<page>" for each two-level entry under sites root.
  # Process substitution avoids SC2095 (ssh swallowing stdin in pipeline).
  local last_project=""
  # shellcheck disable=SC2029  # intentional client-side expansion of $BIGBLACK_ROOT
  while IFS=/ read -r proj page; do
    [[ -z "$proj" ]] && continue
    if [[ "$proj" != "$last_project" ]]; then
      echo ""
      echo "  /$proj/"
      last_project="$proj"
    fi
    [[ -n "$page" ]] && echo "    /$page"
  done < <(ssh "$BIGBLACK_SSH" "find '$BIGBLACK_ROOT' -mindepth 1 -maxdepth 2 -type d -printf '%P\n' 2>/dev/null | sort")
}

cmd_unpublish() {
  local local_dir="${1:?unpublish <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  local remote_path url
  remote_path="$(build_remote_path "$local_dir")"
  url="$(build_url "$local_dir")"
  echo "About to remove: $BIGBLACK_SSH:$remote_path"
  echo "URL that will 404: $url"
  read -r -p "Confirm unpublish? (yes/NO) " ans
  [[ "$ans" == "yes" ]] || { echo "aborted"; exit 0; }
  # shellcheck disable=SC2029  # intentional client-side expansion of $remote_path
  ssh "$BIGBLACK_SSH" "rm -rf '$remote_path'"
  echo "✓ unpublished"
}

case "${1:-}" in
  nav)       shift; cmd_nav       "$@" ;;
  push)      shift; cmd_push      "$@" ;;
  check)     shift; cmd_check     "$@" ;;
  url)       shift; cmd_url       "$@" ;;
  list)              cmd_list ;;
  unpublish) shift; cmd_unpublish "$@" ;;
  *)
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  nav <local-dir>         Regenerate site-map + auto-nav (no network)
  push <local-dir>        Build nav + validate + rsync to bigblack
  check <local-dir>       Build nav + validate (lychee + orphan-page check)
  url <local-dir>         Print the URL where <local-dir> publishes to
  list                    List all published pages on bigblack
  unpublish <local-dir>   Remove the page from bigblack

Environment overrides:
  SITE_PROJECT_NAME       Project namespace (default: from git remote, or
                          basename of the working tree when not in a git repo)
  SITE_BIGBLACK_SSH       SSH alias (default: bigblack)
  SITE_BIGBLACK_ROOT      Remote root (default: /home/tca/sites)
  SITE_BASE_URL           Public URL (default: https://bigblack.tail0f299b.ts.net:8448)
  CLAUDE_PLUGIN_ROOT      Plugin install path (set automatically by Claude
                          Code when this script is invoked via the skill;
                          used as a fallback when scripts/build-nav.py is
                          not present in the consuming repo)
EOF
    exit 1 ;;
esac
