#!/usr/bin/env bash
# site.sh — publish a static HTML directory to a remote host over SSH.
# Modeled on scripts/blob.sh from opendeviationbar-patterns. Adapt freely
# into other repos: copy this file, copy tasks/site.toml, copy
# scripts/check-orphan-pages.py, and you're done.
#
# Subcommands:
#   nav <local-dir>         Regenerate site-map.html + auto-nav rail + search index
#   search <local-dir>      Rebuild Pagefind search index only (no nav rebuild)
#   push <local-dir>        Build nav + validate + rsync to <host>:<root>/<project>/<page>/
#   check <local-dir>       Build nav + validate only (lychee + orphan-page detector)
#   url <local-dir>         Print the URL where <local-dir> would publish to
#   list                    List all published projects/pages on the publish host
#   unpublish <local-dir>   Remove the page from the publish host (asks for confirmation)
#
# URL format:
#   $SITE_BASE_URL/<project>/<page>/
#     <project>  derived from `git remote get-url origin` basename (or
#                $SITE_PROJECT_NAME override)
#     <page>     basename of <local-dir>
#
# The publish host is NOT configured by default — see the SITE_* variables
# below. nav/search/check are purely local and need no configuration.
#
# Gate: every push runs lychee + orphan-page check FIRST. If either fails,
# nothing reaches the server. The validation is the only gate — there is no
# semantic-release here. Push-side gating, by design.

set -euo pipefail

# Repo detection: prefer git toplevel; fall back to PWD so site.sh works
# in non-git directories too (e.g. a one-off site assembled in /tmp).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Publish-host configuration. There is deliberately NO built-in default: this
# script ships in a public marketplace, and a default pointing at one
# maintainer's host both leaks that host's name to every installer and gives
# them a confusing failure when it does not resolve. Configure it instead —
# either by exporting the three SITE_* variables, or by dropping them in a
# config file that simply does not exist on a machine that has not opted in.
# The local-only subcommands (nav, search, check) never read these and work
# with no configuration at all.
SITE_CONFIG="${SITE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/html-showcase/site.env}"
if [[ -f "$SITE_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$SITE_CONFIG"
fi

SSH_HOST="${SITE_SSH_HOST:-}"
REMOTE_ROOT="${SITE_REMOTE_ROOT:-}"
SERVER_BASE_URL="${SITE_BASE_URL:-}"

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

# Guard the subcommands that talk to the publish host (push, url, list,
# unpublish). Fails LOUD rather than silently: the user explicitly asked to
# publish, so quietly doing nothing would be the wrong substitute. The purely
# local subcommands (nav, search, check) never call this.
require_remote_config() {
  local missing=()
  [[ -n "$SSH_HOST" ]]        || missing+=("SITE_SSH_HOST")
  [[ -n "$REMOTE_ROOT" ]]     || missing+=("SITE_REMOTE_ROOT")
  [[ -n "$SERVER_BASE_URL" ]] || missing+=("SITE_BASE_URL")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "✗ publish host is not configured — missing: ${missing[*]}" >&2
    echo "  This skill ships with no default host on purpose; point it at your own." >&2
    echo "  Either export them, or create $SITE_CONFIG containing:" >&2
    echo "      SITE_SSH_HOST=myhost            # ssh alias or hostname" >&2
    echo "      SITE_REMOTE_ROOT=/home/you/sites" >&2
    echo "      SITE_BASE_URL=https://myhost.example.com:8448" >&2
    echo "  See references/publishing.md for the full server setup." >&2
    exit 1
  fi
}

# Resolve the URL where a local dir publishes to
build_url() {
  local local_dir="$1"
  local project page
  require_remote_config
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  echo "$SERVER_BASE_URL/$project/$page/"
}

# Resolve the remote path on the publish host
build_remote_path() {
  local local_dir="$1"
  local project page
  require_remote_config
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  echo "$REMOTE_ROOT/$project/$page"
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
#   2. $(cc-plugin-root html-showcase)/skills/page-template/scripts/build-nav.py
#      (injected into the environment when the skill is invoked from Claude Code)
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
  # Accepts: <local-dir> [--skip-search]
  # The --skip-search flag is the wired-up consumer for the
  # NO_HTMLSHOWCASE_SEARCH=1 env knob in pre-push.template.
  local local_dir=""
  local skip_search=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-search) skip_search=1; shift ;;
      *) local_dir="$1"; shift ;;
    esac
  done
  [[ -n "$local_dir" ]] || { echo "usage: site.sh nav <local-dir> [--skip-search]" >&2; exit 1; }
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  local build_nav
  build_nav="$(resolve_build_nav)"
  if [[ -z "$build_nav" ]]; then
    echo "✗ build-nav.py not found." >&2
    echo "  Easiest fix: invoke /html-showcase:setup from Claude Code." >&2
    echo "  Manual fix:  bash \$(cc-plugin-root html-showcase)/skills/page-template/scripts/install.sh" >&2
    exit 1
  fi
  echo "→ regenerating site-map + auto-nav for $local_dir"
  python3 "$build_nav" --root "$local_dir"
  if [[ $skip_search -eq 1 ]]; then
    echo "  (skipping search-index rebuild via --skip-search)"
  else
    # Always re-build the search index too — search is a default
    # feature, not an opt-in. cmd_search degrades gracefully if pagefind
    # is missing.
    cmd_search "$local_dir"
  fi
}

# pagefind is fetched separately (Rust single-binary release). Resolution
# order: $PAGEFIND_BIN, then $HOME/.local/bin/pagefind, then PATH lookup.
resolve_pagefind() {
  if [[ -n "${PAGEFIND_BIN:-}" && -x "$PAGEFIND_BIN" ]]; then
    echo "$PAGEFIND_BIN"
    return
  fi
  if [[ -x "$HOME/.local/bin/pagefind" ]]; then
    echo "$HOME/.local/bin/pagefind"
    return
  fi
  command -v pagefind 2>/dev/null || echo ""
}

cmd_search() {
  local local_dir="${1:?search <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  local pagefind
  pagefind="$(resolve_pagefind)"
  if [[ -z "$pagefind" ]]; then
    # Search is a default feature, but a missing binary should NOT block
    # the publish flow. Warn loudly and continue with whatever index is
    # already at <local-dir>/pagefind/ (or none, in which case the search
    # box renders inert until the user installs pagefind and re-runs).
    echo "⚠ pagefind not found — skipping search-index rebuild." >&2
    echo "  Install: brew install pagefind" >&2
    echo "  (or:     curl -fsSL https://github.com/CloudCannon/pagefind/releases/latest \\" >&2
    echo "             | … see https://pagefind.app/docs/installation/ )" >&2
    return 0
  fi
  # Sanity-check the binary actually runs before invoking it. ABI
  # mismatches (e.g., user upgraded macOS 13→15, or downloaded the
  # arm64 binary on an Intel Mac) would otherwise show up as a buried
  # "killed" message swallowed by our grep filter downstream.
  if ! "$pagefind" --version >/dev/null 2>&1; then
    echo "⚠ pagefind binary at $pagefind failed --version check." >&2
    echo "  Likely cause: architecture mismatch or corrupted download." >&2
    echo "  Reinstall: brew reinstall pagefind  (or rm $pagefind and re-fetch)" >&2
    return 0
  fi
  echo "→ rebuilding Pagefind search index for $local_dir"
  # Pre-clean any stale or half-built index from a previous killed run.
  # Without this, a SIGINT mid-pagefind leaves orphan chunks that the
  # next run won't auto-overwrite — the server would serve a half-broken
  # search until the user noticed and intervened.
  #
  # SYMLINK GUARD: refuse to follow a symlinked pagefind/ — `rm -rf`
  # on a symlink-to-directory deletes the TARGET's contents, not the
  # link. If a user symlinked pagefind/ to a shared cache outside the
  # site root, that cache would be wiped on every nav rebuild. (Caught
  # by the round-3 adversarial audit.)
  pf_dir="${local_dir%/}/pagefind"
  if [[ -L "$pf_dir" ]]; then
    echo "✗ $pf_dir is a symlink — refusing to rm -rf (would delete the link's target)." >&2
    echo "  Resolve manually: replace the symlink with a real directory before running search." >&2
    return 1
  fi
  rm -rf "$pf_dir"
  if ! "$pagefind" --site "${local_dir%/}" 2>&1 | grep -E '(Indexed|Finished|error|Error)'; then
    : # captured output already piped
  fi
  # Sanity: pagefind didn't write its UI assets → search will 404.
  if [[ ! -f "${local_dir%/}/pagefind/pagefind-ui.js" ]]; then
    echo "⚠ pagefind ran but didn't produce pagefind-ui.js — index may be incomplete." >&2
    return 1
  fi
}

cmd_check() {
  local local_dir="${1:?check <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }

  # Always regenerate nav before validating — sitemap is the SSoT for the
  # page graph, and lychee/orphan-check both depend on it being fresh.
  cmd_nav "$local_dir"

  echo "→ validating $local_dir"

  # Lychee link check.
  # Disable pipefail for the lychee pipe: a non-zero lychee exit (broken
  # links) interacts with `set -e` to abort the whole script BEFORE we
  # reach the if-block that prints remediation hints. By dropping
  # pipefail just for this pipe, we capture the exit code via
  # PIPESTATUS and print our own actionable diagnosis.
  require lychee "brew install lychee  (or: cargo install lychee)"
  local lychee_config="$local_dir/lychee.toml"
  local lychee_status=0
  set +o pipefail
  if [[ -f "$lychee_config" ]]; then
    echo "  lychee (config: $lychee_config)"
    lychee --config "$lychee_config" "$local_dir"/**/*.html 2>&1 | tail -20
  else
    echo "  lychee (no config; using defaults)"
    lychee "$local_dir"/**/*.html 2>&1 | tail -20
  fi
  lychee_status=${PIPESTATUS[0]}
  set -o pipefail
  if [[ $lychee_status -ne 0 ]]; then
    echo "✗ lychee found broken links — aborting" >&2
    echo "  Review the report above, fix the offending URLs / file paths," >&2
    echo "  then re-run:  scripts/site.sh check $local_dir" >&2
    echo "  (To allowlist a host, add it to the [exclude] section of $local_dir/lychee.toml.)" >&2
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

  # 2. Compute provenance values (write the file ONLY after rsync
  # succeeds; otherwise a torn rsync would leave a `.published.json`
  # claiming the publish completed when the server was actually mid-write).
  local commit_sha timestamp project page url remote_path source_repo dirty
  commit_sha="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  dirty=""
  if ! git -C "$REPO_ROOT" diff --quiet -- "$local_dir" 2>/dev/null; then
    dirty="-dirty"
  fi
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  project="$(project_name)"
  page="$(page_name "$local_dir")"
  url="$(build_url "$local_dir")"
  remote_path="$(build_remote_path "$local_dir")"
  source_repo="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo unknown)"

  # 3. Rsync to the publish host — abort on SSH or rsync failure BEFORE
  # stamping provenance. A failure here means the live site wasn't updated.
  #
  # $SSH_HOST is whatever alias you configured; if you resolve it via
  # Tailscale MagicDNS and Tailscale isn't running, the SSH attempt fails
  # with a name-resolution error after a brief delay. The post-failure
  # message below mentions Tailscale explicitly so the user knows
  # what's missing rather than chasing SSH-key debug paths.
  echo "→ rsync $local_dir/ → $SSH_HOST:$remote_path/"
  # shellcheck disable=SC2029  # intentional client-side expansion of $remote_path
  if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "$SSH_HOST" "mkdir -p '$remote_path'"; then
    echo "✗ SSH to $SSH_HOST failed — site not published." >&2
    echo "  Common causes:" >&2
    echo "    • Tailscale not running   (if you resolve the host via MagicDNS)" >&2
    echo "    • SSH keys not loaded     (BatchMode=yes prevents interactive auth)" >&2
    echo "    • publish host offline" >&2
    echo "  Quick diagnose:  ssh $SSH_HOST echo ok" >&2
    echo "  See references/publishing.md for the publish-host setup." >&2
    return 1
  fi
  if ! rsync -av --delete \
        --timeout=30 \
        -e "ssh -o ConnectTimeout=15 -o BatchMode=yes" \
        --exclude '.git/' \
        --exclude '.DS_Store' \
        --exclude '*.swp' \
        --exclude 'node_modules/' \
        --exclude '__pycache__/' \
        --exclude '.venv/' \
        --exclude '.published.json.tmp.*' \
        "$local_dir/" "$SSH_HOST:$remote_path/"; then
    echo "✗ rsync failed — site may be partially updated. Re-run scripts/site.sh push <site> to retry." >&2
    return 1
  fi

  # 4. Stamp provenance only AFTER rsync confirmed success. Atomic via
  # tmp + mv so a SIGINT during this step doesn't leave an unparseable
  # `.published.json`. Write to local; rsync's already done — the
  # next push (or a fresh re-run) will mirror this stamp to the server.
  local tmpfile
  tmpfile=$(mktemp "$local_dir/.published.json.tmp.XXXXXX")
  cat > "$tmpfile" <<JSON
{
  "project": "$project",
  "page": "$page",
  "commit": "${commit_sha}${dirty}",
  "published_utc": "$timestamp",
  "source_repo": "$source_repo",
  "url": "$url"
}
JSON
  mv -f "$tmpfile" "$local_dir/.published.json"

  echo ""
  echo "✓ published"
  echo "  URL:    $url"
  echo "  Path:   $SSH_HOST:$remote_path"
  echo "  Commit: ${commit_sha}${dirty}"
}

cmd_url() {
  local local_dir="${1:?url <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  build_url "$local_dir"
}

cmd_list() {
  require_remote_config
  echo "=== $SERVER_BASE_URL ==="
  # Single SSH call: print "<project>/<page>" for each two-level entry under sites root.
  # Process substitution avoids SC2095 (ssh swallowing stdin in pipeline).
  local last_project=""
  # shellcheck disable=SC2029  # intentional client-side expansion of $REMOTE_ROOT
  while IFS=/ read -r proj page; do
    [[ -z "$proj" ]] && continue
    if [[ "$proj" != "$last_project" ]]; then
      echo ""
      echo "  /$proj/"
      last_project="$proj"
    fi
    [[ -n "$page" ]] && echo "    /$page"
  done < <(ssh "$SSH_HOST" "find '$REMOTE_ROOT' -mindepth 1 -maxdepth 2 -type d -printf '%P\n' 2>/dev/null | sort")
}

cmd_unpublish() {
  local local_dir="${1:?unpublish <local-dir>}"
  [[ -d "$local_dir" ]] || { echo "not a directory: $local_dir" >&2; exit 1; }
  local remote_path url
  remote_path="$(build_remote_path "$local_dir")"
  url="$(build_url "$local_dir")"
  echo "About to remove: $SSH_HOST:$remote_path"
  echo "URL that will 404: $url"
  read -r -p "Confirm unpublish? (yes/NO) " ans
  [[ "$ans" == "yes" ]] || { echo "aborted"; exit 0; }
  # shellcheck disable=SC2029  # intentional client-side expansion of $remote_path
  ssh "$SSH_HOST" "rm -rf '$remote_path'"
  echo "✓ unpublished"
}

case "${1:-}" in
  nav)       shift; cmd_nav       "$@" ;;
  search)    shift; cmd_search    "$@" ;;
  push)      shift; cmd_push      "$@" ;;
  check)     shift; cmd_check     "$@" ;;
  url)       shift; cmd_url       "$@" ;;
  list)              cmd_list ;;
  unpublish) shift; cmd_unpublish "$@" ;;
  *)
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  nav <local-dir>         Regenerate site-map + auto-nav + search index
  search <local-dir>      Rebuild Pagefind search index only
  push <local-dir>        Build nav + validate + rsync to the publish host
  check <local-dir>       Build nav + validate (lychee + orphan-page check)
  url <local-dir>         Print the URL where <local-dir> publishes to
  list                    List all published pages on the publish host
  unpublish <local-dir>   Remove the page from the publish host

Environment overrides:
  SITE_PROJECT_NAME       Project namespace (default: from git remote, or
                          basename of the working tree when not in a git repo)
  SITE_CONFIG             Config file sourced at startup (default:
                          \${XDG_CONFIG_HOME:-~/.config}/html-showcase/site.env)
  SITE_SSH_HOST           SSH alias or hostname of the publish host (no default)
  SITE_REMOTE_ROOT        Remote root directory, e.g. /home/you/sites (no default)
  SITE_BASE_URL           Public base URL, e.g. https://myhost.example.com:8448
                          (no default)
                          The three above are REQUIRED by push/url/list/unpublish
                          and unused by nav/search/check.
  CLAUDE_PLUGIN_ROOT      Plugin install path (injected when the skill is
                          invoked from Claude Code; used as a fallback when
                          scripts/build-nav.py is not present in the consuming repo)
  PAGEFIND_BIN            Override path to the pagefind binary (default:
                          ~/.local/bin/pagefind, falling back to PATH)
EOF
    exit 1 ;;
esac
