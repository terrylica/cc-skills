#!/usr/bin/env bash
# sync-commands-to-settings.sh - Sync plugin skills to ~/.claude/commands/
#
# Called during post-release to ensure any new slash commands are automatically
# available in the user's ~/.claude/commands/ without manual intervention.
#
# Design:
# - Scans skills/{name}/SKILL.md from each plugin in the marketplace (v11.54.0+)
# - Copies to ~/.claude/commands/ with plugin:skill namespacing
# - Preserves existing user commands that aren't from cc-skills plugins
# - Uses marketplace path (not cache) for reliability
# - Adds provenance comment to track cc-skills origin

set -euo pipefail

COMMANDS_DIR="$HOME/.claude/commands"
BACKUP_DIR="$HOME/.claude/backups"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/cc-skills"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Backup commands directory
backup_commands() {
    mkdir -p "$BACKUP_DIR"
    if [[ -d "$COMMANDS_DIR" ]] && ls "$COMMANDS_DIR"/*.md &>/dev/null; then
        local ts
        ts=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$BACKUP_DIR/commands.$ts"
        cp "$COMMANDS_DIR"/*.md "$BACKUP_DIR/commands.$ts/" 2>/dev/null || true
    fi
}

# Main
main() {
    echo "→ Syncing plugin skills to ~/.claude/commands/..."

    # Ensure commands dir exists
    mkdir -p "$COMMANDS_DIR"

    # Backup
    backup_commands

    # Remove all cc-skills commands first (clean slate approach)
    # cc-skills commands are identified by the provenance comment in YAML frontmatter
    local removed=0
    for cmd_file in "$COMMANDS_DIR"/*.md; do
        [[ -f "$cmd_file" ]] || continue
        if head -5 "$cmd_file" | grep -q "cc-skills-marketplace"; then
            rm "$cmd_file"
            ((removed++))
        fi
    done

    # Find all skill files in marketplace plugins (canonical: skills/{skill}/SKILL.md)
    local commands_added=0
    for skill_md in "$MARKETPLACE_DIR"/plugins/*/skills/*/SKILL.md; do
        [[ -f "$skill_md" ]] || continue

        # path: .../plugins/{plugin}/skills/{skill}/SKILL.md
        local plugin_name
        plugin_name=$(basename "$(dirname "$(dirname "$(dirname "$skill_md")")")")

        local cmd_name
        cmd_name=$(basename "$(dirname "$skill_md")")

        # Target: ~/.claude/commands/plugin:skill.md
        local target="$COMMANDS_DIR/${plugin_name}:${cmd_name}.md"

        # Copy with provenance marker injected after frontmatter opening ---
        # The marker lets us identify cc-skills commands for clean removal
        if head -1 "$skill_md" | grep -q "^---"; then
            {
                echo "---"
                echo "# cc-skills-marketplace: ${plugin_name}/${cmd_name}"
                # Skip the opening --- and output the rest
                tail -n +2 "$skill_md"
            } > "$target"
        else
            # No frontmatter — copy as-is with provenance at top
            {
                echo "---"
                echo "# cc-skills-marketplace: ${plugin_name}/${cmd_name}"
                echo "---"
                cat "$skill_md"
            } > "$target"
        fi

        ((commands_added++))
    done

    info "Commands synced: $commands_added skill(s) from cc-skills marketplace"
}

main "$@"
