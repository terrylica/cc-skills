#!/usr/bin/env bash
# migrate-from-autonomous-loop.sh — Rewrite ~/.claude/settings.json after the
# autonomous-loop → autoloop rename (v17.0.0).
#
# Idempotent: safe to run multiple times. No-op if no legacy paths remain.
# Atomic: writes to a tempfile in the same directory then renames.
# Backed up: copies the pre-edit settings.json to ~/.claude/backups/.
#
# Called automatically by /autoloop:setup when legacy paths are detected.
# Can also be run by hand: bash plugins/autoloop/scripts/migrate-from-autonomous-loop.sh

set -euo pipefail

SETTINGS="${SETTINGS:-$HOME/.claude/settings.json}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.claude/backups}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1" >&2; }

main() {
  if [[ ! -f "$SETTINGS" ]]; then
    info "No settings.json at $SETTINGS — nothing to migrate."
    return 0
  fi

  if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    err "settings.json is malformed; refusing to rewrite. Fix JSON first."
    return 1
  fi

  if ! grep -q -e 'plugins/autonomous-loop/' -e '"autonomous-loop@cc-skills"' "$SETTINGS"; then
    info "No legacy autonomous-loop paths in settings.json — already migrated."
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  local ts
  ts=$(date +%s)
  local backup="$BACKUP_DIR/settings.json.pre-autoloop.$ts"
  cp "$SETTINGS" "$backup"
  info "Backed up to $backup"

  # Build a jq program that walks the entire settings tree and rewrites:
  #   * any string containing "plugins/autonomous-loop/" → "plugins/autoloop/"
  #   * top-level key "autonomous-loop@cc-skills" → "autoloop@cc-skills"
  local tmp
  tmp=$(mktemp "${SETTINGS}.tmp.XXXXXX")
  trap 'rm -f "$tmp"' EXIT

  # Walk the entire tree:
  #   * rewrite any string containing "plugins/autonomous-loop/" → "plugins/autoloop/"
  #   * rename any object key "autonomous-loop@cc-skills" → "autoloop@cc-skills"
  jq '
    walk(
      if type == "string" then
        gsub("plugins/autonomous-loop/"; "plugins/autoloop/")
      elif type == "object" then
        with_entries(
          if .key == "autonomous-loop@cc-skills"
          then .key = "autoloop@cc-skills"
          else .
          end
        )
      else .
      end
    )
  ' "$SETTINGS" > "$tmp"

  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    err "Rewrite produced invalid JSON; aborting (original untouched)."
    return 1
  fi

  mv "$tmp" "$SETTINGS"
  trap - EXIT

  info "Migrated settings.json (legacy paths and plugin key rewritten)."
  if grep -q 'plugins/autonomous-loop/' "$SETTINGS"; then
    warn "Some legacy paths remain — inspect manually."
    grep -n 'plugins/autonomous-loop/' "$SETTINGS" || true
    return 1
  fi
}

main "$@"
