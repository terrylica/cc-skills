#!/usr/bin/env bash
# manage-hooks.sh - Install/uninstall statusline-tools Stop hook
#
# MIT License
# Copyright (c) 2025 Terry Li
#
# Usage:
#   manage-hooks.sh install    Add Stop hook to settings.json
#   manage-hooks.sh uninstall  Remove Stop hook from settings.json
#   manage-hooks.sh status     Show current hook configuration
#
# The Stop hook runs lychee link validation and lint-relative-paths
# on session end, caching results for status line display.

set -euo pipefail

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
HOOK_SCRIPT="${PLUGIN_ROOT}/hooks/lychee-stop-hook.sh"
SETTINGS_FILE="${HOME}/.claude/settings.json"
HOOK_TIMEOUT=30000

# Colors for output
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[33m'
CYAN='\033[36m'
RESET='\033[0m'

# === Helper Functions ===

log_info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1" >&2
}

# Check if jq is available
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed. Install with: brew install jq"
        exit 1
    fi
}

# Ensure settings.json exists with valid JSON
ensure_settings_file() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        log_info "Creating $SETTINGS_FILE"
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Validate JSON
    if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        log_error "Invalid JSON in $SETTINGS_FILE"
        exit 1
    fi
}

# Create backup before modification
backup_settings() {
    local backup_dir="${HOME}/.claude/backups"
    mkdir -p "$backup_dir"
    local backup_file="${backup_dir}/settings.json.$(date +%Y%m%d-%H%M%S).bak"
    cp "$SETTINGS_FILE" "$backup_file"
    log_info "Backup created: $backup_file"
}

# Check if our hook is already installed
is_hook_installed() {
    jq -e --arg script "$HOOK_SCRIPT" '
        .hooks.Stop // [] |
        any(
            .hooks[]? |
            .command == $script
        )
    ' "$SETTINGS_FILE" >/dev/null 2>&1
}

# === Commands ===

cmd_install() {
    check_dependencies
    ensure_settings_file

    # Check if hook script exists
    if [[ ! -x "$HOOK_SCRIPT" ]]; then
        log_error "Hook script not found or not executable: $HOOK_SCRIPT"
        exit 1
    fi

    # Check current state
    if is_hook_installed; then
        log_success "Stop hook already installed"
        return 0
    fi

    backup_settings

    # Write new hook entry atomically
    local tmp_file
    tmp_file=$(mktemp)

    # Add our hook to the Stop hooks array
    # Creates .hooks and .hooks.Stop if they don't exist
    jq --arg script "$HOOK_SCRIPT" --argjson timeout "$HOOK_TIMEOUT" '
        # Ensure hooks object exists
        .hooks //= {} |
        # Ensure Stop array exists
        .hooks.Stop //= [] |
        # Add our hook entry
        .hooks.Stop += [{
            "hooks": [{
                "type": "command",
                "command": $script,
                "timeout": $timeout
            }]
        }]
    ' "$SETTINGS_FILE" > "$tmp_file"

    if ! jq empty "$tmp_file" 2>/dev/null; then
        log_error "Failed to generate valid JSON"
        rm -f "$tmp_file"
        exit 1
    fi

    mv "$tmp_file" "$SETTINGS_FILE"
    log_success "Stop hook installed"
    log_info "  Script:  $HOOK_SCRIPT"
    log_info "  Timeout: ${HOOK_TIMEOUT}ms"
    log_info "Restart Claude Code for changes to take effect"
}

cmd_uninstall() {
    check_dependencies
    ensure_settings_file

    # Check current state
    if ! is_hook_installed; then
        log_success "Stop hook not found (already uninstalled)"
        return 0
    fi

    backup_settings

    # Remove our hook entry atomically
    local tmp_file
    tmp_file=$(mktemp)

    # Remove entries that contain our hook script
    jq --arg script "$HOOK_SCRIPT" '
        .hooks.Stop = (
            .hooks.Stop // [] |
            map(
                select(
                    (.hooks // []) |
                    all(.command != $script)
                )
            )
        ) |
        # Clean up empty Stop array
        if (.hooks.Stop | length) == 0 then
            del(.hooks.Stop)
        else
            .
        end |
        # Clean up empty hooks object
        if (.hooks | length) == 0 then
            del(.hooks)
        else
            .
        end
    ' "$SETTINGS_FILE" > "$tmp_file"

    if ! jq empty "$tmp_file" 2>/dev/null; then
        log_error "Failed to generate valid JSON"
        rm -f "$tmp_file"
        exit 1
    fi

    mv "$tmp_file" "$SETTINGS_FILE"
    log_success "Stop hook uninstalled"
    log_info "  Removed: $HOOK_SCRIPT"
    log_info "Restart Claude Code for changes to take effect"
}

cmd_status() {
    check_dependencies

    echo -e "${CYAN}=== statusline-tools Stop Hook Status ===${RESET}"
    echo ""

    # Plugin root
    echo -e "${CYAN}Plugin Root:${RESET}"
    echo "  $PLUGIN_ROOT"
    echo ""

    # Hook script
    echo -e "${CYAN}Hook Script:${RESET}"
    if [[ -x "$HOOK_SCRIPT" ]]; then
        echo -e "  ${GREEN}✓${RESET} $HOOK_SCRIPT"
    elif [[ -f "$HOOK_SCRIPT" ]]; then
        echo -e "  ${YELLOW}⚠${RESET} $HOOK_SCRIPT (not executable)"
    else
        echo -e "  ${RED}✗${RESET} $HOOK_SCRIPT (not found)"
    fi
    echo ""

    # Installation status
    echo -e "${CYAN}Installation Status:${RESET}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        if is_hook_installed; then
            echo -e "  ${GREEN}✓ Stop hook is installed${RESET}"

            # Show the hook details
            local hook_info
            hook_info=$(jq -r --arg script "$HOOK_SCRIPT" '
                .hooks.Stop[]? |
                select(.hooks[]?.command == $script) |
                .hooks[] |
                select(.command == $script) |
                "    Timeout: \(.timeout // "default")ms"
            ' "$SETTINGS_FILE" 2>/dev/null)
            if [[ -n "$hook_info" ]]; then
                echo "$hook_info"
            fi
        else
            echo -e "  ${YELLOW}○ Stop hook is not installed${RESET}"
        fi
    else
        echo -e "  ${YELLOW}settings.json not found${RESET}"
    fi
    echo ""

    # Other Stop hooks (for context)
    echo -e "${CYAN}Other Stop Hooks:${RESET}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        local other_hooks
        other_hooks=$(jq -r --arg script "$HOOK_SCRIPT" '
            .hooks.Stop[]?.hooks[]? |
            select(.command != $script) |
            .command
        ' "$SETTINGS_FILE" 2>/dev/null | head -5)

        if [[ -n "$other_hooks" ]]; then
            while IFS= read -r hook; do
                echo "  - $hook"
            done <<< "$other_hooks"
        else
            echo "  (none)"
        fi
    fi
    echo ""

    # Cache files status
    echo -e "${CYAN}Cache Files (current directory):${RESET}"
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null) || git_root="."

    if [[ -f "$git_root/.lychee-results.json" ]]; then
        local lychee_errors lychee_time
        lychee_errors=$(jq -r '.errors // 0' "$git_root/.lychee-results.json" 2>/dev/null)
        lychee_time=$(jq -r '.timestamp // "unknown"' "$git_root/.lychee-results.json" 2>/dev/null)
        echo -e "  ${GREEN}✓${RESET} .lychee-results.json (errors: $lychee_errors, updated: $lychee_time)"
    else
        echo -e "  ${YELLOW}○${RESET} .lychee-results.json (not found - run hook to create)"
    fi

    if [[ -f "$git_root/.lint-relative-paths-results.txt" ]]; then
        local path_violations
        path_violations=$(grep -oE 'Found [0-9]+ violation' "$git_root/.lint-relative-paths-results.txt" 2>/dev/null | grep -oE '[0-9]+' || echo 0)
        echo -e "  ${GREEN}✓${RESET} .lint-relative-paths-results.txt (violations: $path_violations)"
    else
        echo -e "  ${YELLOW}○${RESET} .lint-relative-paths-results.txt (not found - run hook to create)"
    fi
}

# === Main ===

usage() {
    echo "Usage: $(basename "$0") [install|uninstall|status]"
    echo ""
    echo "Commands:"
    echo "  install    Add Stop hook to ~/.claude/settings.json"
    echo "  uninstall  Remove Stop hook from ~/.claude/settings.json"
    echo "  status     Show current hook configuration"
    exit 1
}

main() {
    local command="${1:-}"

    case "$command" in
        install)
            cmd_install
            ;;
        uninstall)
            cmd_uninstall
            ;;
        status)
            cmd_status
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
