#!/usr/bin/env bash
# manage-hooks.sh - Idempotent dotfiles-tools hooks installer for settings.json
#
# Usage: manage-hooks.sh [install|uninstall|status|restore [latest|<n>]]
#
# Design principles:
# - Idempotent: safe to run multiple times
# - Atomic: uses temp file + mv to prevent corruption
# - Validated: checks JSON validity before committing
# - Recoverable: creates timestamped backups

set -euo pipefail

# === Configuration ===
SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
HOOKS_BASE="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/dotfiles-tools/hooks"
MARKER="dotfiles-tools/hooks/"  # Unique identifier in command paths

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
        info "dotfiles-tools hooks are INSTALLED ($count hook entries found)"
        echo ""
        echo "Installed hooks:"
        jq -r '.hooks | to_entries[] | select(.value[] | .hooks[] | .command | contains("'"$MARKER"'")) | "  - \(.key): \(.value[] | select(.hooks[] | .command | contains("'"$MARKER"'")) | .matcher)"' "$SETTINGS"
        echo ""
        echo "Backups available:"
        if [[ -d "$BACKUP_DIR" ]]; then
            ls -1 "$BACKUP_DIR"/settings.json.backup.* 2>/dev/null | while read -r f; do
                echo "  - $(basename "$f" | sed 's/settings.json.backup.//')"
            done || echo "  (none)"
        else
            echo "  (none)"
        fi
        return 0
    else
        info "dotfiles-tools hooks are NOT installed"
        return 1
    fi
}

do_install() {
    ensure_settings_exists
    check_dependencies

    # Idempotency check
    if is_installed; then
        warn "dotfiles-tools hooks are already installed. Use 'uninstall' first to reinstall."
        do_status
        return 0
    fi

    # Verify hook scripts exist
    local posttooluse_script="$HOOKS_BASE/chezmoi-sync-reminder.sh"

    if [[ ! -x "$posttooluse_script" ]]; then
        die "PostToolUse script not found or not executable: $posttooluse_script"
    fi

    # Create backup
    local timestamp
    timestamp=$(create_backup)
    info "Created backup: settings.json.backup.$timestamp"

    # Prepare hook entry (using $HOME literal, not expanded)
    local posttooluse_entry='{"matcher":"Edit|Write","hooks":[{"type":"command","command":"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/dotfiles-tools/hooks/chezmoi-sync-reminder.sh","timeout":5000}]}'

    # Create temp file for atomic write
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Apply modifications using jq
    jq --argjson post "$posttooluse_entry" '
        .hooks //= {} |
        .hooks.PostToolUse //= [] |
        .hooks.PostToolUse += [$post]
    ' "$SETTINGS" > "$temp_file"

    # Validate the new JSON
    if ! validate_json "$temp_file"; then
        die "Generated invalid JSON. Aborting. Original file unchanged."
    fi

    # Atomic move
    mv "$temp_file" "$SETTINGS"
    trap - EXIT

    info "dotfiles-tools hooks installed successfully!"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
    echo ""
    echo "To undo: /dotfiles:hooks restore latest"

    do_status
}

do_uninstall() {
    ensure_settings_exists
    check_dependencies

    # Idempotency check
    if ! is_installed; then
        warn "dotfiles-tools hooks are not installed. Nothing to uninstall."
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

    info "dotfiles-tools hooks uninstalled successfully!"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
    echo ""
    echo "To undo: /dotfiles:hooks restore latest"
}

list_backups() {
    # Returns array of backup files sorted newest first
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -1t "$BACKUP_DIR"/settings.json.backup.* 2>/dev/null || true
    fi
}

do_restore() {
    local selector="${1:-}"
    local -a backups
    mapfile -t backups < <(list_backups)

    # No backups available
    if [[ ${#backups[@]} -eq 0 ]]; then
        die "No backups found in $BACKUP_DIR"
    fi

    local backup_file=""

    # No argument: list backups with numbers
    if [[ -z "$selector" ]]; then
        info "Available backups (newest first):"
        echo ""
        local i=1
        for f in "${backups[@]}"; do
            local ts
            ts=$(basename "$f" | sed 's/settings.json.backup.//')
            local formatted_ts
            formatted_ts=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            echo "  $i) $formatted_ts"
            ((i++))
        done
        echo ""
        echo "Usage: /dotfiles:hooks restore <number>  - Restore specific backup"
        echo "       /dotfiles:hooks restore latest    - Restore most recent backup"
        return 0
    fi

    # "latest" keyword: restore most recent
    if [[ "$selector" == "latest" ]]; then
        backup_file="${backups[0]}"
        info "Selecting most recent backup"
    # Numeric selector: restore by index
    elif [[ "$selector" =~ ^[0-9]+$ ]]; then
        local index=$((selector - 1))  # Convert to 0-indexed
        if [[ $index -lt 0 || $index -ge ${#backups[@]} ]]; then
            die "Invalid backup number: $selector. Valid range: 1-${#backups[@]}"
        fi
        backup_file="${backups[$index]}"
    else
        die "Invalid selector: $selector. Use a number (1-${#backups[@]}) or 'latest'"
    fi

    # Validate selected backup
    if ! validate_json "$backup_file"; then
        die "Backup file is corrupt (invalid JSON): $backup_file"
    fi

    local ts
    ts=$(basename "$backup_file" | sed 's/settings.json.backup.//')

    # Create backup of current state before restore
    local current_timestamp
    current_timestamp=$(create_backup)
    info "Backed up current state: settings.json.backup.$current_timestamp"

    cp "$backup_file" "$SETTINGS"
    info "Restored from backup: $ts"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
}

# === Main ===

ACTION="${1:-status}"
RESTORE_SELECTOR="${2:-}"

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
    restore)
        do_restore "$RESTORE_SELECTOR"
        ;;
    *)
        die "Unknown action: $ACTION. Use: install|uninstall|status|restore [latest|<n>]"
        ;;
esac
