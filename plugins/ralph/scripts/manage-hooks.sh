#!/usr/bin/env bash
# manage-hooks.sh - Idempotent ralph hooks installer for settings.json
#
# Usage: manage-hooks.sh [install|uninstall|status]
#
# Design principles:
# - Idempotent: safe to run multiple times
# - Atomic: uses temp file + mv to prevent corruption
# - Validated: checks JSON validity before committing
# - Version-agnostic: uses marketplace path, not cache path

set -euo pipefail

# === Configuration ===
SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
# Use marketplace path (version-agnostic) not cache path
HOOKS_BASE="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph/hooks"
MARKER="ralph/hooks/"  # Unique identifier in command paths

# === Colors for output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === Helper Functions ===

die() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}WARN:${NC} $1"
}

check_dependencies() {
    if ! command -v jq &>/dev/null; then
        die "jq is required but not installed. Install with: brew install jq"
    fi
}

validate_json() {
    local file="$1"
    if ! jq empty "$file" 2>/dev/null; then
        return 1
    fi
    return 0
}

ensure_settings_exists() {
    if [[ ! -f "$SETTINGS" ]]; then
        die "Settings file not found: $SETTINGS"
    fi
    if ! validate_json "$SETTINGS"; then
        die "Settings file is not valid JSON: $SETTINGS"
    fi
}

create_backup() {
    mkdir -p "$BACKUP_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/settings.json.backup.$timestamp"
    cp "$SETTINGS" "$backup_file"
    echo "$timestamp"
}

is_installed() {
    # Check if any hook command contains the marker
    jq -e '.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))' "$SETTINGS" >/dev/null 2>&1
}

count_hooks() {
    jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0"
}

# === Core Operations ===

do_status() {
    ensure_settings_exists
    local count
    count=$(count_hooks)

    if [[ "$count" -gt 0 ]]; then
        info "ralph hooks are INSTALLED ($count hook entries found)"
        echo ""
        echo "Installed hooks:"
        jq -r '.hooks | to_entries[] | select(.value[] | .hooks[] | .command | contains("'"$MARKER"'")) | "  - \(.key)"' "$SETTINGS" | sort -u
        return 0
    else
        info "ralph hooks are NOT installed"
        echo ""
        echo "To install: /ralph:hooks install"
        return 1
    fi
}

do_install() {
    ensure_settings_exists
    check_dependencies

    # Idempotency check
    if is_installed; then
        warn "ralph hooks are already installed. Use 'uninstall' first to reinstall."
        do_status
        return 0
    fi

    # Verify hook scripts exist
    local stop_script="$HOOKS_BASE/loop-until-done.py"
    local pretooluse_script="$HOOKS_BASE/archive-plan.sh"

    if [[ ! -f "$stop_script" ]]; then
        die "Stop hook script not found: $stop_script"
    fi
    if [[ ! -f "$pretooluse_script" ]]; then
        die "PreToolUse hook script not found: $pretooluse_script"
    fi

    # Create backup
    local timestamp
    timestamp=$(create_backup)
    info "Created backup: settings.json.backup.$timestamp"

    # Prepare hook entries (using $HOME literal, not expanded)
    # Note: Using marketplace path which is version-agnostic
    local stop_entry='{"hooks":[{"type":"command","command":"uv run $HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph/hooks/loop-until-done.py","timeout":30000}]}'
    local pretooluse_entry='{"matcher":"Write|Edit","hooks":[{"type":"command","command":"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph/hooks/archive-plan.sh","timeout":5000}]}'

    # Create temp file for atomic write
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Apply modifications using jq
    jq --argjson stop "$stop_entry" --argjson pre "$pretooluse_entry" '
        .hooks //= {} |
        .hooks.Stop //= [] |
        .hooks.Stop += [$stop] |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [$pre]
    ' "$SETTINGS" > "$temp_file"

    # Validate the new JSON
    if ! validate_json "$temp_file"; then
        die "Generated invalid JSON. Aborting. Original file unchanged."
    fi

    # Atomic move
    mv "$temp_file" "$SETTINGS"
    trap - EXIT

    info "ralph hooks installed successfully!"
    echo ""
    echo "Hooks installed:"
    echo "  - Stop: loop-until-done.py (autonomous loop control)"
    echo "  - PreToolUse: archive-plan.sh (plan file archival)"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
}

do_uninstall() {
    ensure_settings_exists
    check_dependencies

    # Idempotency check
    if ! is_installed; then
        warn "ralph hooks are not installed. Nothing to uninstall."
        return 0
    fi

    # Create backup
    local timestamp
    timestamp=$(create_backup)
    info "Created backup: settings.json.backup.$timestamp"

    # Create temp file for atomic write
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Remove entries containing marker from all hook arrays
    jq '
        .hooks |= (
            to_entries | map(
                .value |= map(
                    select(.hooks | all(.command | contains("'"$MARKER"'") | not))
                )
            ) | from_entries
        )
    ' "$SETTINGS" > "$temp_file"

    # Validate the new JSON
    if ! validate_json "$temp_file"; then
        die "Generated invalid JSON. Aborting. Original file unchanged."
    fi

    # Atomic move
    mv "$temp_file" "$SETTINGS"
    trap - EXIT

    info "ralph hooks uninstalled successfully!"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
}

# === Main ===

ACTION="${1:-status}"

case "$ACTION" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    status)
        do_status
        ;;
    *)
        die "Unknown action: $ACTION. Use: install|uninstall|status"
        ;;
esac
