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

main() {
    echo "→ Pruning cc-skills marketplace-path hook entries from settings.json..."

    if [[ ! -f "$SETTINGS" ]]; then
        warn "settings.json not found at $SETTINGS — nothing to prune"
        return 0
    fi

    backup_settings

    # Count cc-skills entries before pruning so we can report what changed.
    local before_count
    before_count=$(jq '
        [.hooks // {} | to_entries[] | .value[]?.hooks[]?.command]
        | map(select(. != null and contains("marketplaces/cc-skills/plugins/")))
        | length
    ' "$SETTINGS")

    # Per-hook filter: drop hooks whose command references the cc-skills
    # marketplace path; if a matcher entry's .hooks array becomes empty
    # after filtering, drop the matcher entry too.
    jq '
        .hooks |= with_entries(
            .value |= (
                map(.hooks |= map(select(.command | contains("marketplaces/cc-skills/plugins/") | not)))
                | map(select(.hooks | length > 0))
            )
        )
    ' "$SETTINGS" > /tmp/settings-pruned.$$.json

    if ! jq empty /tmp/settings-pruned.$$.json 2>/dev/null; then
        warn "Pruning produced invalid JSON — leaving settings.json untouched"
        rm -f /tmp/settings-pruned.$$.json
        exit 1
    fi

    mv /tmp/settings-pruned.$$.json "$SETTINGS"

    local after_count
    after_count=$(jq '
        [.hooks // {} | to_entries[] | .value[]?.hooks[]?.command]
        | map(select(. != null and contains("marketplaces/cc-skills/plugins/")))
        | length
    ' "$SETTINGS")

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
