#!/usr/bin/env bash
# manage-statusline.sh - Install/uninstall statusline-tools status line
#
# MIT License
# Copyright (c) 2025 Terry Li
#
# Usage:
#   manage-statusline.sh install    Install status line to settings.json
#   manage-statusline.sh uninstall  Remove status line from settings.json
#   manage-statusline.sh status     Show current configuration
#
# Settings.json modification:
#   - Installs statusLine object with type "command"
#   - Points to plugin's custom-statusline.sh
#   - Uses atomic write (temp file + mv) for safety

set -euo pipefail

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# Use marketplace path with $HOME for portability and auto-updates
# This path is version-agnostic - updates automatically when plugin updates
MARKETPLACE_PATH='$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools'
STATUSLINE_SCRIPT_SETTINGS="${MARKETPLACE_PATH}/statusline/custom-statusline.sh"

# For local validation, resolve the actual path
STATUSLINE_SCRIPT_RESOLVED="${HOME}/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools/statusline/custom-statusline.sh"

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

# === Commands ===

cmd_install() {
    check_dependencies
    ensure_settings_file

    # Validate script exists at marketplace location
    if [[ ! -x "$STATUSLINE_SCRIPT_RESOLVED" ]]; then
        log_error "Status line script not found at marketplace location"
        log_error "  Expected: $STATUSLINE_SCRIPT_RESOLVED"
        log_info "  Run '/plugin install cc-skills@statusline-tools' first"
        exit 1
    fi

    # Check current state - normalize $HOME for comparison
    local current current_resolved
    current=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
    current_resolved="${current//\$HOME/$HOME}"

    if [[ -n "$current" ]]; then
        # Check if already pointing to marketplace (either $HOME or absolute form)
        if [[ "$current" == "$STATUSLINE_SCRIPT_SETTINGS" ]] || \
           [[ "$current_resolved" == "$STATUSLINE_SCRIPT_RESOLVED" ]]; then
            log_success "Status line already installed (marketplace path)"
            log_info "  Updates automatically with /plugin update"
            return 0
        fi
        log_warn "Replacing existing statusLine configuration"
        log_info "  Current: $current"
        log_info "  New:     $STATUSLINE_SCRIPT_SETTINGS"
    fi

    backup_settings

    # Write marketplace path with $HOME for portability
    local tmp_file
    tmp_file=$(mktemp)

    jq --arg script "$STATUSLINE_SCRIPT_SETTINGS" '.statusLine = {
        "type": "command",
        "command": $script,
        "padding": 0
    }' "$SETTINGS_FILE" > "$tmp_file"

    if ! jq empty "$tmp_file" 2>/dev/null; then
        log_error "Failed to generate valid JSON"
        rm -f "$tmp_file"
        exit 1
    fi

    mv "$tmp_file" "$SETTINGS_FILE"
    log_success "Status line installed (marketplace path)"
    log_info "  Script: $STATUSLINE_SCRIPT_SETTINGS"
    log_info "  ✓ Auto-updates with /plugin update"
    log_info "Restart Claude Code for changes to take effect"
}

cmd_uninstall() {
    check_dependencies
    ensure_settings_file

    # Check current state
    local current
    current=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)

    if [[ -z "$current" ]]; then
        log_success "No statusLine configuration found (already uninstalled)"
        return 0
    fi

    backup_settings

    # Remove statusLine atomically
    local tmp_file
    tmp_file=$(mktemp)

    jq 'del(.statusLine)' "$SETTINGS_FILE" > "$tmp_file"

    if ! jq empty "$tmp_file" 2>/dev/null; then
        log_error "Failed to generate valid JSON"
        rm -f "$tmp_file"
        exit 1
    fi

    mv "$tmp_file" "$SETTINGS_FILE"
    log_success "Status line uninstalled"
    log_info "  Removed: $current"
    log_info "Restart Claude Code for changes to take effect"
}

cmd_status() {
    check_dependencies

    echo -e "${CYAN}=== statusline-tools Status ===${RESET}"
    echo ""

    # Marketplace script location
    echo -e "${CYAN}Marketplace Script:${RESET}"
    if [[ -x "$STATUSLINE_SCRIPT_RESOLVED" ]]; then
        echo -e "  ${GREEN}✓${RESET} $STATUSLINE_SCRIPT_SETTINGS"
    elif [[ -f "$STATUSLINE_SCRIPT_RESOLVED" ]]; then
        echo -e "  ${YELLOW}⚠${RESET} $STATUSLINE_SCRIPT_SETTINGS (not executable)"
    else
        echo -e "  ${RED}✗${RESET} $STATUSLINE_SCRIPT_SETTINGS (not installed)"
        echo -e "  ${YELLOW}Run: /plugin install cc-skills@statusline-tools${RESET}"
    fi
    echo ""

    # Settings.json configuration
    echo -e "${CYAN}settings.json Configuration:${RESET}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        local status_type status_cmd status_padding status_cmd_resolved
        status_type=$(jq -r '.statusLine.type // empty' "$SETTINGS_FILE" 2>/dev/null)
        status_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
        status_padding=$(jq -r '.statusLine.padding // "N/A"' "$SETTINGS_FILE" 2>/dev/null)
        status_cmd_resolved="${status_cmd//\$HOME/$HOME}"

        if [[ -n "$status_type" ]]; then
            echo "  Type:    $status_type"
            echo "  Command: $status_cmd"
            echo "  Padding: $status_padding"

            # Check if pointing to marketplace path
            if [[ "$status_cmd" == "$STATUSLINE_SCRIPT_SETTINGS" ]] || \
               [[ "$status_cmd_resolved" == "$STATUSLINE_SCRIPT_RESOLVED" ]]; then
                echo -e "  ${GREEN}✓ Marketplace path (auto-updates)${RESET}"
            else
                echo -e "  ${YELLOW}⚠ Custom path (won't auto-update)${RESET}"
                echo -e "  ${YELLOW}  Run: /statusline-tools:setup install${RESET}"
            fi
        else
            echo -e "  ${YELLOW}No statusLine configured${RESET}"
            echo -e "  ${YELLOW}  Run: /statusline-tools:setup install${RESET}"
        fi
    else
        echo -e "  ${YELLOW}settings.json not found${RESET}"
    fi
    echo ""

    # Dependencies
    echo -e "${CYAN}Dependencies:${RESET}"
    if command -v lychee &>/dev/null; then
        local lychee_version
        lychee_version=$(lychee --version 2>/dev/null | head -1)
        echo -e "  ${GREEN}✓${RESET} lychee: $lychee_version"
    else
        echo -e "  ${YELLOW}○${RESET} lychee: not installed (optional, install with: mise install lychee)"
    fi

    if command -v jq &>/dev/null; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null)
        echo -e "  ${GREEN}✓${RESET} jq: $jq_version"
    else
        echo -e "  ${RED}✗${RESET} jq: not installed (required)"
    fi

    local lint_script="${PLUGIN_ROOT}/scripts/lint-relative-paths"
    if [[ -x "$lint_script" ]]; then
        echo -e "  ${GREEN}✓${RESET} lint-relative-paths: bundled"
    else
        echo -e "  ${RED}✗${RESET} lint-relative-paths: not found"
    fi
    echo ""

    # Global ignore patterns
    echo -e "${CYAN}Global Ignore Patterns:${RESET}"
    local ignore_file="${HOME}/.claude/lint-relative-paths-ignore"
    if [[ -f "$ignore_file" ]]; then
        echo -e "  ${GREEN}✓${RESET} $ignore_file"
        echo "  Patterns:"
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            # Show comments in yellow, patterns in green
            if [[ "$line" == \#* ]]; then
                echo -e "    ${YELLOW}$line${RESET}"
            else
                echo -e "    ${GREEN}• $line${RESET}"
            fi
        done < "$ignore_file"
    else
        echo -e "  ${YELLOW}○${RESET} No global ignore file"
        echo "    Create: ~/.claude/lint-relative-paths-ignore"
        echo "    Manage: /statusline-tools:ignore add <pattern>"
    fi
}

cmd_deps() {
    echo -e "${CYAN}=== statusline-tools Dependencies ===${RESET}"
    echo ""

    # Check mise
    if ! command -v mise &>/dev/null; then
        log_error "mise is required for dependency installation"
        echo "  Install mise: https://mise.jdx.dev/"
        exit 1
    fi

    log_info "mise detected: $(mise --version 2>/dev/null | head -1)"
    echo ""

    # Install lychee via mise
    echo -e "${CYAN}Installing lychee via mise...${RESET}"
    if mise install lychee; then
        log_success "lychee installed successfully"
    else
        log_error "Failed to install lychee"
        exit 1
    fi

    # Verify installation
    echo ""
    echo -e "${CYAN}Verification:${RESET}"
    if command -v lychee &>/dev/null; then
        local lychee_version
        lychee_version=$(lychee --version 2>/dev/null | head -1)
        echo -e "  ${GREEN}✓${RESET} lychee: $lychee_version"
    else
        echo -e "  ${YELLOW}⚠${RESET} lychee: installed but not in PATH"
        echo "  You may need to restart your shell or run: eval \"\$(mise activate bash)\""
    fi
}

# === Main ===

usage() {
    echo "Usage: $(basename "$0") [install|uninstall|status|deps]"
    echo ""
    echo "Commands:"
    echo "  install    Install status line to ~/.claude/settings.json"
    echo "  uninstall  Remove status line from ~/.claude/settings.json"
    echo "  status     Show current configuration and dependencies"
    echo "  deps       Install lychee via mise"
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
        deps)
            cmd_deps
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
