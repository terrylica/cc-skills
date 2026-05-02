#!/usr/bin/env bash
# install.sh — one-shot bootstrap for the html-showcase pipeline.
#
# Drops the three pipeline scripts (build-nav.py, check-orphan-pages.py,
# site.sh) into <repo>/scripts/, ensures **/.published.json is gitignored,
# and optionally seeds a starter site directory with index.html +
# overrides.css.example + lychee.toml.
#
# Idempotent: re-running with no changes is a no-op. Non-destructive:
# never overwrites an existing file unless --force is passed.
#
# Usage:
#   bash install.sh [--repo <path>] [--site <name>] [--force] [--check] [--hook]
#
#   --repo <path>   Target repo root (default: $PWD or `git rev-parse
#                   --show-toplevel` if invoked inside a git tree)
#   --site <name>   Also scaffold <repo>/<name>/ with starter HTML files
#                   (default: skip; pass e.g. `--site contractor-site`
#                   to seed one)
#   --force         Overwrite existing scripts/templates if they differ
#   --check         Preflight only: report what's already installed and
#                   what would be installed, exit 0 if everything is
#                   already in place, exit 10 if anything is missing.
#                   Pairs with the /html-showcase:setup skill.
#   --hook          Also install a pre-push git hook that regenerates the
#                   sitemap + Pagefind search index and rsyncs every
#                   tracked site dir to bigblack on `git push main`.
#                   Wires <repo>/.githooks/ via `git config
#                   core.hooksPath .githooks`. Non-blocking; failure
#                   never blocks the push.
#
# After install, the workflow is:
#   scripts/site.sh nav   <site-dir>   # regenerate sitemap + auto-nav
#   scripts/site.sh check <site-dir>   # nav + lychee + orphan-page
#   scripts/site.sh push  <site-dir>   # nav + check + rsync to bigblack

set -euo pipefail

# ----------------------------------------------------------------------
# Resolve the source skill directory regardless of how install.sh was
# invoked (via $CLAUDE_PLUGIN_ROOT, via a clone of cc-skills, or via a
# direct path).
#
# Use $0 (works under both bash and zsh) instead of BASH_SOURCE[0]
# (bash-only) so users who accidentally run `zsh install.sh` still get
# a working bootstrap.
# ----------------------------------------------------------------------
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_SRC="$SKILL_DIR/scripts"
TEMPLATES_SRC="$SKILL_DIR/templates"

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
REPO=""
SITE=""
FORCE=0
CHECK_ONLY=0
INSTALL_HOOK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO="$2";  shift 2 ;;
    --site)  SITE="$2";  shift 2 ;;
    --force) FORCE=1;    shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --hook)  INSTALL_HOOK=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# *//'
      exit 0 ;;
    *)
      echo "unknown flag: $1 (use --help)" >&2
      exit 2 ;;
  esac
done

# Resolve repo root — prefer git, fall back to PWD.
if [[ -z "$REPO" ]]; then
  if REPO="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    REPO="$PWD"
  fi
fi
REPO="$(cd "$REPO" && pwd)"

if [[ ! -d "$REPO" ]]; then
  echo "✗ target repo does not exist: $REPO" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Toolchain preflight: python3 must be ≥ 3.10 (build-nav.py uses
# pathlib's walk_up=True on 3.12+ with a 3.10/3.11 fallback). Failing
# loudly here beats a cryptic TypeError on first nav rebuild.
# ----------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    py_ver="$(python3 --version 2>&1 || echo unknown)"
    echo "✗ python3 is too old: ${py_ver}. Need Python 3.10 or newer." >&2
    echo "  Install: brew install python@3.13  (or: mise use python@3.13)" >&2
    exit 1
  fi
else
  echo "✗ python3 not on PATH. Install: brew install python@3.13" >&2
  exit 1
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "→ preflight check for $REPO"
else
  echo "→ installing html-showcase pipeline into $REPO"
fi

# Tracks "missing or out-of-date" count for --check exit code.
MISSING_COUNT=0

# ----------------------------------------------------------------------
# Helper: copy a file unless it already exists with identical content.
# Honors --force for a clean overwrite. Under --check, never copies —
# only reports.
# ----------------------------------------------------------------------
copy_if_new() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    echo "  ✗ source missing: $src" >&2
    return 1
  fi
  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      echo "  = $label (unchanged)"
      return 0
    fi
    if [[ $CHECK_ONLY -eq 1 ]]; then
      echo "  ✗ $label differs from canonical (would update on install)"
      MISSING_COUNT=$((MISSING_COUNT + 1))
      return 0
    fi
    if [[ $FORCE -ne 1 ]]; then
      echo "  ⚠ $label exists and differs — pass --force to overwrite"
      return 0
    fi
  elif [[ $CHECK_ONLY -eq 1 ]]; then
    echo "  ✗ $label not installed"
    MISSING_COUNT=$((MISSING_COUNT + 1))
    return 0
  fi
  # Explicit 0755 — don't trust the source file's bits (the user might
  # have a tight umask or a checkout with stripped exec bits) and don't
  # trust stat to be portable across filesystems.
  install -m 0755 "$src" "$dst"
  echo "  ✓ $label"
}

# ----------------------------------------------------------------------
# 1. Pipeline scripts → <repo>/scripts/
# ----------------------------------------------------------------------
[[ $CHECK_ONLY -eq 1 ]] || mkdir -p "$REPO/scripts"
copy_if_new "$SCRIPTS_SRC/build-nav.py"         "$REPO/scripts/build-nav.py"         "scripts/build-nav.py"
copy_if_new "$SCRIPTS_SRC/check-orphan-pages.py" "$REPO/scripts/check-orphan-pages.py" "scripts/check-orphan-pages.py"
copy_if_new "$SCRIPTS_SRC/site.sh"              "$REPO/scripts/site.sh"              "scripts/site.sh"

# ----------------------------------------------------------------------
# 2. .gitignore — ensure provenance + Pagefind index aren't committed.
#
# Two patterns:
#   **/.published.json   — per-push provenance stamp (regenerated each push)
#   **/pagefind/         — Pagefind binary's static index (regenerated each
#                          nav build; committing it causes diff churn when
#                          team members have different pagefind versions)
#
# We use a BOM-aware variant of grep -qxF: if a user's .gitignore was
# saved with a UTF-8 BOM, `grep -qxF` against the raw line "**/foo" can
# fail-to-find an entry that's actually present. Strip BOM via sed first.
# ----------------------------------------------------------------------
GITIGNORE="$REPO/.gitignore"
PUBLISHED_PATTERN='**/.published.json'
PAGEFIND_PATTERN='**/pagefind/'

# Test for a pattern's presence in .gitignore, BOM-tolerant.
gitignore_has() {
  local pat="$1"
  [[ -f "$GITIGNORE" ]] || return 1
  sed '1s/^\xEF\xBB\xBF//' "$GITIGNORE" | grep -qxF "$pat"
}

# Single-pass append: collect all missing patterns, write them all in
# one append operation. Atomic enough that a SIGINT between the first
# and second append doesn't leave the repo in a "I already added one
# pattern, re-run won't add the second" state.
missing_patterns=()
missing_comments=()
for pair in \
    "$PUBLISHED_PATTERN|published-page provenance manifests" \
    "$PAGEFIND_PATTERN|Pagefind static search index (regenerated per nav build)"
do
  pat="${pair%%|*}"
  comment="${pair#*|}"
  if [[ ! -f "$GITIGNORE" ]] || ! gitignore_has "$pat"; then
    missing_patterns+=("$pat")
    missing_comments+=("$comment")
  else
    echo "  = .gitignore already lists $pat"
  fi
done

if [[ ${#missing_patterns[@]} -gt 0 ]]; then
  if [[ $CHECK_ONLY -eq 1 ]]; then
    for pat in "${missing_patterns[@]}"; do
      echo "  ✗ .gitignore missing entry $pat"
      MISSING_COUNT=$((MISSING_COUNT + 1))
    done
  else
    # Build the full block in memory FIRST, then write in one shot.
    # Resolving "does the file exist?" BEFORE opening the append
    # redirect avoids the shellcheck SC2094 read+write-in-same-pipeline
    # warning, and also lets us either-write-everything-or-nothing on
    # SIGINT (no half-applied state across the two patterns).
    gitignore_existed=0
    [[ -f "$GITIGNORE" ]] && gitignore_existed=1
    block=""
    if [[ $gitignore_existed -eq 1 ]]; then
      block=$'\n'
    fi
    hash_tag='#'
    for i in "${!missing_patterns[@]}"; do
      block+="${hash_tag} html-showcase: ${missing_comments[$i]}"$'\n'
      block+="${missing_patterns[$i]}"$'\n'
    done
    printf '%s' "$block" >> "$GITIGNORE"
    for pat in "${missing_patterns[@]}"; do
      echo "  ✓ appended $pat to .gitignore"
    done
  fi
fi

# If `pagefind/` is already TRACKED by git (committed before being
# gitignored), gitignoring it doesn't untrack the existing copies. The
# user will keep seeing diff churn every time the index regenerates.
# This is a one-time-fix situation — surface it loudly so they know.
if [[ $CHECK_ONLY -ne 1 ]] && command -v git >/dev/null 2>&1; then
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$REPO" ls-files --error-unmatch -- '**/pagefind/' >/dev/null 2>&1; then
      echo "  ⚠ pagefind/ is already tracked by git. To stop committing the index, run:" >&2
      echo "      git -C $REPO rm -r --cached '**/pagefind/' && git commit -m 'untrack pagefind index'" >&2
    fi
  fi
fi

# ----------------------------------------------------------------------
# 3. (optional) Seed a starter site dir with index.html + overrides + lychee
# ----------------------------------------------------------------------
if [[ -n "$SITE" ]]; then
  SITE_DIR="$REPO/$SITE"
  [[ $CHECK_ONLY -eq 1 ]] || mkdir -p "$SITE_DIR"
  echo "→ seeding site directory: $SITE_DIR"
  copy_if_new "$TEMPLATES_SRC/index.html"             "$SITE_DIR/index.html"        "$SITE/index.html"
  copy_if_new "$TEMPLATES_SRC/overrides.css.example"  "$SITE_DIR/overrides.css"     "$SITE/overrides.css"
  copy_if_new "$TEMPLATES_SRC/lychee.toml"            "$SITE_DIR/lychee.toml"       "$SITE/lychee.toml"
  if [[ $CHECK_ONLY -ne 1 ]]; then
    echo "  → fill {{ PLACEHOLDERS }} in $SITE/index.html, then:"
    echo "      python3 $REPO/scripts/build-nav.py --root $SITE_DIR"
  fi
fi

# ----------------------------------------------------------------------
# 3.5. Pre-push hook validation/install.
#
# When --hook is passed: install/refresh the hook in .githooks/pre-push
# and wire core.hooksPath. When --check is passed AND a hook is already
# present at .githooks/pre-push, validate it even WITHOUT --hook so a
# user upgrading the plugin can detect a stale committed hook without
# having to remember to add --hook each time.
# ----------------------------------------------------------------------
EXISTING_HOOK="$REPO/.githooks/pre-push"
if [[ $INSTALL_HOOK -ne 1 && $CHECK_ONLY -eq 1 && -f "$EXISTING_HOOK" ]]; then
  HOOK_SRC="$SCRIPTS_SRC/pre-push.template"
  if [[ -f "$HOOK_SRC" ]] && ! cmp -s "$HOOK_SRC" "$EXISTING_HOOK"; then
    echo "→ pre-push hook present at .githooks/pre-push but differs from canonical:"
    echo "  ✗ .githooks/pre-push is stale (would update on install --hook --force)"
    MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
fi

if [[ $INSTALL_HOOK -eq 1 ]]; then
  HOOK_SRC="$SCRIPTS_SRC/pre-push.template"
  HOOK_DST="$REPO/.githooks/pre-push"
  echo "→ installing pre-push hook: $HOOK_DST"
  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "  ✗ template missing at $HOOK_SRC" >&2
    [[ $CHECK_ONLY -eq 1 ]] && MISSING_COUNT=$((MISSING_COUNT + 1))
  else
    if [[ -f "$HOOK_DST" ]] && cmp -s "$HOOK_SRC" "$HOOK_DST"; then
      echo "  = .githooks/pre-push (unchanged)"
    elif [[ -f "$HOOK_DST" && $FORCE -ne 1 && $CHECK_ONLY -ne 1 ]]; then
      echo "  ⚠ .githooks/pre-push exists and differs — pass --force to overwrite"
    elif [[ $CHECK_ONLY -eq 1 ]]; then
      if [[ -f "$HOOK_DST" ]]; then
        echo "  ✗ .githooks/pre-push differs from canonical (would update on install)"
      else
        echo "  ✗ .githooks/pre-push not installed"
      fi
      MISSING_COUNT=$((MISSING_COUNT + 1))
    else
      mkdir -p "$REPO/.githooks"
      install -m 755 "$HOOK_SRC" "$HOOK_DST"
      echo "  ✓ .githooks/pre-push"
    fi
  fi
  # Wire core.hooksPath so the hook actually fires. Idempotent and
  # collision-aware: if another hook engine (Husky, lefthook, pre-commit)
  # already pointed core.hooksPath somewhere else, refuse to clobber it
  # silently. The user gets a clear error and can pass --force to
  # override after they've decided whether to migrate.
  if [[ $CHECK_ONLY -ne 1 ]]; then
    # `--local` reads ONLY the repo's .git/config, NOT global/system. A
    # global `core.hooksPath = .husky` (set in ~/.config/git/config) is
    # the user's environment choice and shouldn't false-positive a
    # collision warning for every repo they install into.
    current_path="$(git -C "$REPO" config --local --get core.hooksPath 2>/dev/null || echo '')"
    if [[ "$current_path" == ".githooks" ]]; then
      echo "  = git config core.hooksPath already set to .githooks"
    elif [[ -n "$current_path" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        git -C "$REPO" config core.hooksPath .githooks
        echo "  ✓ git config core.hooksPath = .githooks (overrode '$current_path' via --force)"
      else
        echo "  ⚠ core.hooksPath is already set to '$current_path' (Husky/lefthook/pre-commit?)" >&2
        echo "    Refusing to override silently. Options:" >&2
        echo "      • Re-run with --force to set core.hooksPath = .githooks" >&2
        echo "      • Manually merge: copy $REPO/.githooks/pre-push into '$current_path/pre-push'" >&2
        echo "      • Skip the hook: use scripts/site.sh push manually instead" >&2
        exit 3
      fi
    else
      git -C "$REPO" config core.hooksPath .githooks
      echo "  ✓ git config core.hooksPath = .githooks"
    fi
  fi
fi

# ----------------------------------------------------------------------
# 4. Summary
# ----------------------------------------------------------------------
if [[ $CHECK_ONLY -eq 1 ]]; then
  if [[ $MISSING_COUNT -eq 0 ]]; then
    echo
    echo "✓ everything in place — no install needed"
    exit 0
  fi
  echo
  echo "$MISSING_COUNT item(s) need installation. Re-run without --check to apply."
  exit 10
fi

cat <<EOF

✓ install complete

Next steps:
  1. (Optional) Add shorthand mise tasks: drop a .mise/tasks/site.toml that
     wraps scripts/site.sh — see references/publishing.md for an example.
  2. Author HTML files in <site-dir>/ and any <site-dir>/<section-slug>/.
     Each subdir of the site root that contains *.html becomes a "section".
  3. Build the sitemap + auto-nav rail:
       python3 scripts/build-nav.py --root <site-dir>
     or, equivalently:
       scripts/site.sh nav <site-dir>
  4. Validate locally:
       scripts/site.sh check <site-dir>
  5. Publish to bigblack via Tailscale:
       scripts/site.sh push <site-dir>

Skill: html-showcase:page-template (cc-skills marketplace)
SSoT for the architecture: $SKILL_DIR/SKILL.md
EOF
