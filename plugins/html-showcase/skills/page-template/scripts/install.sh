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
#   bash install.sh [--repo <path>] [--site <name>] [--force]
#
#   --repo <path>   Target repo root (default: $PWD or `git rev-parse
#                   --show-toplevel` if invoked inside a git tree)
#   --site <name>   Also scaffold <repo>/<name>/ with starter HTML files
#                   (default: skip; pass e.g. `--site contractor-site`
#                   to seed one)
#   --force         Overwrite existing scripts/templates if they differ
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
# ----------------------------------------------------------------------
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_SRC="$SKILL_DIR/scripts"
TEMPLATES_SRC="$SKILL_DIR/templates"

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
REPO=""
SITE=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO="$2";  shift 2 ;;
    --site)  SITE="$2";  shift 2 ;;
    --force) FORCE=1;    shift ;;
    -h|--help)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# *//'
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

echo "→ installing html-showcase pipeline into $REPO"

# ----------------------------------------------------------------------
# Helper: copy a file unless it already exists with identical content.
# Honors --force for a clean overwrite.
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
    if [[ $FORCE -ne 1 ]]; then
      echo "  ⚠ $label exists and differs — pass --force to overwrite"
      return 0
    fi
  fi
  install -m "$(stat -f '%A' "$src" 2>/dev/null || stat -c '%a' "$src")" "$src" "$dst"
  echo "  ✓ $label"
}

# ----------------------------------------------------------------------
# 1. Pipeline scripts → <repo>/scripts/
# ----------------------------------------------------------------------
mkdir -p "$REPO/scripts"
copy_if_new "$SCRIPTS_SRC/build-nav.py"         "$REPO/scripts/build-nav.py"         "scripts/build-nav.py"
copy_if_new "$SCRIPTS_SRC/check-orphan-pages.py" "$REPO/scripts/check-orphan-pages.py" "scripts/check-orphan-pages.py"
copy_if_new "$SCRIPTS_SRC/site.sh"              "$REPO/scripts/site.sh"              "scripts/site.sh"

# ----------------------------------------------------------------------
# 2. .gitignore — ensure **/.published.json is ignored
# ----------------------------------------------------------------------
GITIGNORE="$REPO/.gitignore"
PUBLISHED_PATTERN='**/.published.json'
if [[ ! -f "$GITIGNORE" ]]; then
  echo "$PUBLISHED_PATTERN" > "$GITIGNORE"
  echo "  ✓ created .gitignore with $PUBLISHED_PATTERN"
elif ! grep -qxF "$PUBLISHED_PATTERN" "$GITIGNORE"; then
  printf '\n# html-showcase: published-page provenance manifests\n%s\n' "$PUBLISHED_PATTERN" >> "$GITIGNORE"
  echo "  ✓ appended $PUBLISHED_PATTERN to .gitignore"
else
  echo "  = .gitignore already lists $PUBLISHED_PATTERN"
fi

# ----------------------------------------------------------------------
# 3. (optional) Seed a starter site dir with index.html + overrides + lychee
# ----------------------------------------------------------------------
if [[ -n "$SITE" ]]; then
  SITE_DIR="$REPO/$SITE"
  mkdir -p "$SITE_DIR"
  echo "→ seeding site directory: $SITE_DIR"
  copy_if_new "$TEMPLATES_SRC/index.html"             "$SITE_DIR/index.html"        "$SITE/index.html"
  copy_if_new "$TEMPLATES_SRC/overrides.css.example"  "$SITE_DIR/overrides.css"     "$SITE/overrides.css"
  copy_if_new "$TEMPLATES_SRC/lychee.toml"            "$SITE_DIR/lychee.toml"       "$SITE/lychee.toml"
  echo "  → fill {{ PLACEHOLDERS }} in $SITE/index.html, then:"
  echo "      python3 $REPO/scripts/build-nav.py --root $SITE_DIR"
fi

# ----------------------------------------------------------------------
# 4. Summary
# ----------------------------------------------------------------------
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
