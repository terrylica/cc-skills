#!/usr/bin/env bash
# manage-hooks.sh - Idempotent ralph hooks installer for settings.json
#
# Usage: manage-hooks.sh [install|uninstall|status]
#
# Design principles:
# - Idempotent: safe to run multiple times
# - Atomic: uses temp file + mv to prevent corruption
# - Validated: checks JSON validity before committing
# - Path-agnostic: auto-detects marketplace, cache, or dev paths
# - Restart-aware: records install timestamp for session detection

set -euo pipefail

# === Configuration ===
SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="ralph/hooks/"  # Unique identifier in command paths
INSTALL_TIMESTAMP_FILE="$HOME/.claude/ralph-hooks-installed-at"

# Auto-detect plugin root with fallback chain:
# 1. CLAUDE_PLUGIN_ROOT (set by Claude Code when running plugin commands)
# 2. Marketplace path (local dev)
# 3. Cache path (GitHub install - find latest version)
# 4. Script's parent directory (fallback)
detect_plugin_root() {
    # Priority 1: Environment variable
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi

    # Priority 2: Marketplace path (local dev)
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi

    # Priority 3: Cache path (GitHub install - latest version)
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/ralph"
    if [[ -d "$cache_base" ]]; then
        # Find latest version directory (highest semver)
        local latest
        latest=$(ls -1 "$cache_base" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$latest" && -d "$cache_base/$latest/hooks" ]]; then
            echo "$cache_base/$latest"
            return
        fi
    fi

    # Priority 4: Relative to script (ultimate fallback)
    echo "$(dirname "$SCRIPT_DIR")"
}

PLUGIN_ROOT="$(detect_plugin_root)"
HOOKS_BASE="$PLUGIN_ROOT/hooks"

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

    # Build hook command paths using detected PLUGIN_ROOT
    # Convert absolute path to $HOME-based for portability in settings.json
    local home_relative="${PLUGIN_ROOT/#$HOME/\$HOME}"
    local stop_cmd="uv run ${home_relative}/hooks/loop-until-done.py"
    local pretooluse_cmd="${home_relative}/hooks/archive-plan.sh"

    # Prepare hook entries using jq for proper JSON escaping
    local stop_entry
    local pretooluse_entry
    stop_entry=$(jq -n --arg cmd "$stop_cmd" '{"hooks":[{"type":"command","command":$cmd,"timeout":30000}]}')
    pretooluse_entry=$(jq -n --arg cmd "$pretooluse_cmd" '{"hooks":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]}')

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

    # Record installation timestamp for restart detection
    date +%s > "$INSTALL_TIMESTAMP_FILE"

    info "ralph hooks installed successfully!"
    echo ""
    echo "Plugin root: $PLUGIN_ROOT"
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
