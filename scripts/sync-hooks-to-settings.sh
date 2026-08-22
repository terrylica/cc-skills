#!/usr/bin/env bash
# sync-hooks-to-settings.sh — Prune cc-skills marketplace-path hook entries.
#
# History (v20.2.3+):
# Plugin hooks are auto-loaded by Claude Code from each plugin's
# `hooks/hooks.json` file in the standard install location. Adding
# the same hooks to ~/.claude/settings.json (with marketplace paths)
# was the original sync strategy but caused DOUBLE registration —
# every hook fired twice per event, observable in the runtime "Ran N
# stop hooks" display as the same script listed twice.
#
# This script now PRUNES any cc-skills marketplace-path entries that
# leaked into settings.json from older releases. It does NOT add any
# new entries. Plugins register their own hooks at session start via
# the auto-load mechanism.
#
# Idempotent. Safe to re-run.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

backup_settings() {
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.backup.$ts"
}

# A settings.json is user-authored, so every level may be absent or null:
# no `hooks` key at all, a matcher list that is null, a matcher entry whose
# `hooks` array is missing, or a hook entry with no `command`. jq's `to_entries`
# and `map` both abort on null ("null (null) has no keys"), which crashed this
# script for anyone whose settings.json simply had no `hooks` key.
#
# Every accessor below therefore defaults before it dereferences, and the prune
# is skipped entirely unless `.hooks` is genuinely an object — a non-object
# `hooks` is malformed input this script must not silently rewrite.
readonly MARKETPLACE_PATH_FRAGMENT='marketplaces/cc-skills/plugins/'

readonly JQ_COUNT_MARKETPLACE_PATH_ENTRIES='
    [ (if (.hooks | type) == "object" then .hooks else {} end)
      | to_entries[]
      | (.value // [])[]
      | (.hooks // [])[]
      | (.command // "")
    ]
    | map(select(contains($fragment)))
    | length
'

readonly JQ_PRUNE_MARKETPLACE_PATH_ENTRIES='
    def prune_matcher_entries:
        [ (. // [])[]
          | .hooks = [ (.hooks // [])[]
                       | select(((.command // "") | contains($fragment)) | not) ]
        ]
        | map(select((.hooks | length) > 0));

    if (.hooks | type) == "object"
    then .hooks |= with_entries(.value |= prune_matcher_entries)
    else .
    end
'

main() {
    echo "→ Pruning cc-skills marketplace-path hook entries from settings.json..."

    if [[ ! -f "$SETTINGS" ]]; then
        warn "settings.json not found at $SETTINGS — nothing to prune"
        return 0
    fi

    backup_settings

    # Count cc-skills entries before pruning so we can report what changed.
    local before_count
    before_count=$(jq --arg fragment "$MARKETPLACE_PATH_FRAGMENT" \
        "$JQ_COUNT_MARKETPLACE_PATH_ENTRIES" "$SETTINGS")

    # Per-hook filter: drop hooks whose command references the cc-skills
    # marketplace path; if a matcher entry's .hooks array becomes empty
    # after filtering, drop the matcher entry too.
    jq --arg fragment "$MARKETPLACE_PATH_FRAGMENT" \
        "$JQ_PRUNE_MARKETPLACE_PATH_ENTRIES" "$SETTINGS" > /tmp/settings-pruned.$$.json

    if ! jq empty /tmp/settings-pruned.$$.json 2>/dev/null; then
        warn "Pruning produced invalid JSON — leaving settings.json untouched"
        rm -f /tmp/settings-pruned.$$.json
        exit 1
    fi

    mv /tmp/settings-pruned.$$.json "$SETTINGS"

    local after_count
    after_count=$(jq --arg fragment "$MARKETPLACE_PATH_FRAGMENT" \
        "$JQ_COUNT_MARKETPLACE_PATH_ENTRIES" "$SETTINGS")

    local removed=$((before_count - after_count))
    if [[ $removed -gt 0 ]]; then
        info "Pruned $removed marketplace-path entr$([[ $removed -eq 1 ]] && echo y || echo ies)"
    else
        info "No cc-skills marketplace-path entries found (already clean)"
    fi

    if [[ $after_count -ne 0 ]]; then
        warn "$after_count cc-skills entr$([[ $after_count -eq 1 ]] && echo y || echo ies) remain (filter mismatch?)"
        exit 1
    fi
}

main "$@"
