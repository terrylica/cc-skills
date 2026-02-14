#!/usr/bin/env bash
# sync-hooks-to-settings.sh - Sync plugin hooks.json to ~/.claude/settings.json
#
# Called during post-release to ensure any new hooks are automatically
# installed in the user's settings.json without manual intervention.
#
# Design:
# - Reads hooks.json from each plugin in the marketplace
# - Merges into settings.json, avoiding duplicates
# - Preserves existing user hooks that aren't from cc-skills plugins
# - Uses marketplace path (not cache) for reliability

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/cc-skills"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Backup settings
backup_settings() {
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.backup.$ts"
}

# Main
main() {
    echo "→ Syncing plugin hooks to settings.json..."

    # Ensure settings exists
    if [[ ! -f "$SETTINGS" ]]; then
        echo '{"hooks": {"PreToolUse": [], "PostToolUse": [], "Stop": []}}' > "$SETTINGS"
    fi

    # Backup
    backup_settings

    # Remove all cc-skills hooks first (clean slate approach)
    jq '
        .hooks.PreToolUse = [.hooks.PreToolUse[]? | select(.hooks[]?.command | contains("cc-skills") | not)] |
        .hooks.PostToolUse = [.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("cc-skills") | not)] |
        .hooks.Stop = [.hooks.Stop[]? | select(.hooks[]?.command | contains("cc-skills") | not)]
    ' "$SETTINGS" > /tmp/settings-clean.json
    mv /tmp/settings-clean.json "$SETTINGS"

    # Find all hooks.json files in marketplace
    local hooks_added=0
    for hooks_file in "$MARKETPLACE_DIR"/plugins/*/hooks/hooks.json; do
        if [[ -f "$hooks_file" ]]; then
            local plugin_name
            plugin_name=$(basename "$(dirname "$(dirname "$hooks_file")")")

            # Read hooks from plugin — must be object format (keyed by event type)
            local hooks_type
            hooks_type=$(jq -r '.hooks | type' "$hooks_file" 2>/dev/null) || continue
            if [[ "$hooks_type" != "object" ]]; then
                warn "Skipping $plugin_name: hooks.json uses $hooks_type format (expected object keyed by event type)"
                continue
            fi

            local plugin_hooks
            plugin_hooks=$(jq '.hooks' "$hooks_file" 2>/dev/null) || continue

            # Add each hook type
            for hook_type in PreToolUse PostToolUse Stop; do
                local type_hooks
                type_hooks=$(echo "$plugin_hooks" | jq ".$hook_type // []")
                if [[ "$type_hooks" != "[]" && "$type_hooks" != "null" ]]; then
                    # Replace ${CLAUDE_PLUGIN_ROOT} with actual marketplace path
                    local plugin_path="\$HOME/.claude/plugins/marketplaces/cc-skills/plugins/$plugin_name"
                    # shellcheck disable=SC2001
                    type_hooks=$(echo "$type_hooks" | sed "s|\\\${CLAUDE_PLUGIN_ROOT}|$plugin_path|g")

                    # Merge into settings
                    jq --argjson new_hooks "$type_hooks" "
                        .hooks.$hook_type = (.hooks.$hook_type // []) + \$new_hooks
                    " "$SETTINGS" > /tmp/settings-merged.json
                    mv /tmp/settings-merged.json "$SETTINGS"
                    ((hooks_added++))
                fi
            done
        fi
    done

    # Deduplicate by matcher + hooks content
    jq '
        .hooks.PreToolUse = (.hooks.PreToolUse | unique_by(.matcher + (.hooks | tostring))) |
        .hooks.PostToolUse = (.hooks.PostToolUse | unique_by(.matcher + (.hooks | tostring))) |
        .hooks.Stop = (.hooks.Stop | unique_by(.hooks | tostring))
    ' "$SETTINGS" > /tmp/settings-dedup.json
    mv /tmp/settings-dedup.json "$SETTINGS"

    # Validate JSON
    if ! jq empty "$SETTINGS" 2>/dev/null; then
        warn "Invalid JSON in settings.json, restoring backup"
        cp "$BACKUP_DIR/settings.json.backup."* "$SETTINGS" 2>/dev/null || true
        exit 1
    fi

    # Count final hooks
    local pretooluse_count posttooluse_count stop_count
    pretooluse_count=$(jq '.hooks.PreToolUse | length' "$SETTINGS")
    posttooluse_count=$(jq '.hooks.PostToolUse | length' "$SETTINGS")
    stop_count=$(jq '.hooks.Stop | length' "$SETTINGS")

    info "Hooks synced: PreToolUse=$pretooluse_count, PostToolUse=$posttooluse_count, Stop=$stop_count"
}

main "$@"
