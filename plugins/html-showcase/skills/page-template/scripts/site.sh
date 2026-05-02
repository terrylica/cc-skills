#!/usr/bin/env bash
# site.sh — publish a static HTML directory to bigblack via Tailscale.
# Modeled on scripts/blob.sh from opendeviationbar-patterns. Adapt freely
# into other repos: copy this file, copy .mise/tasks/site.toml, copy
# scripts/check-orphan-pages.py, and you're done.
#
# Subcommands:
#   push <local-dir>        Validate + rsync to bigblack:~/sites/<project>/<page>/
#   check <local-dir>       Validate only (lychee + orphan-page detector)
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

REPO_ROOT="$(git rev-parse --show-toplevel)"
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

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }

cmd_check() {
  local local_dir="${1:?check <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }

  echo "→ validating $local_dir"

  # Lychee link check
  require lychee
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
  push)      shift; cmd_push      "$@" ;;
  check)     shift; cmd_check     "$@" ;;
  url)       shift; cmd_url       "$@" ;;
  list)              cmd_list ;;
  unpublish) shift; cmd_unpublish "$@" ;;
  *)
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  push <local-dir>        Validate + rsync to bigblack
  check <local-dir>       Validate only (lychee + orphan-page check)
  url <local-dir>         Print the URL where <local-dir> publishes to
  list                    List all published pages on bigblack
  unpublish <local-dir>   Remove the page from bigblack

Environment overrides:
  SITE_PROJECT_NAME       Project namespace (default: from git remote)
  SITE_BIGBLACK_SSH       SSH alias (default: bigblack)
  SITE_BIGBLACK_ROOT      Remote root (default: /home/tca/sites)
  SITE_BASE_URL           Public URL (default: https://bigblack.tail0f299b.ts.net:8448)
EOF
    exit 1 ;;
esac
