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
STATUSLINE_SCRIPT="${PLUGIN_ROOT}/statusline/custom-statusline.sh"
SETTINGS_FILE="${HOME}/.claude/settings.json"

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

    # Check if statusline script exists
    if [[ ! -x "$STATUSLINE_SCRIPT" ]]; then
        log_error "Status line script not found or not executable: $STATUSLINE_SCRIPT"
        exit 1
    fi

    # Check current state
    local current
    current=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)

    if [[ -n "$current" ]]; then
        if [[ "$current" == "$STATUSLINE_SCRIPT" ]]; then
            log_success "Status line already installed and points to this plugin"
            return 0
        fi
        log_warn "Replacing existing statusLine configuration"
        log_info "  Current: $current"
        log_info "  New:     $STATUSLINE_SCRIPT"
    fi

    backup_settings

    # Write new configuration atomically
    local tmp_file
    tmp_file=$(mktemp)

    jq --arg script "$STATUSLINE_SCRIPT" '.statusLine = {
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
    log_success "Status line installed"
    log_info "  Script: $STATUSLINE_SCRIPT"
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

    # Plugin root
    echo -e "${CYAN}Plugin Root:${RESET}"
    echo "  $PLUGIN_ROOT"
    echo ""

    # Status line script
    echo -e "${CYAN}Status Line Script:${RESET}"
    if [[ -x "$STATUSLINE_SCRIPT" ]]; then
        echo -e "  ${GREEN}✓${RESET} $STATUSLINE_SCRIPT"
    elif [[ -f "$STATUSLINE_SCRIPT" ]]; then
        echo -e "  ${YELLOW}⚠${RESET} $STATUSLINE_SCRIPT (not executable)"
    else
        echo -e "  ${RED}✗${RESET} $STATUSLINE_SCRIPT (not found)"
    fi
    echo ""

    # Settings.json configuration
    echo -e "${CYAN}settings.json Configuration:${RESET}"
    if [[ -f "$SETTINGS_FILE" ]]; then
        local status_type status_cmd status_padding
        status_type=$(jq -r '.statusLine.type // empty' "$SETTINGS_FILE" 2>/dev/null)
        status_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
        status_padding=$(jq -r '.statusLine.padding // "N/A"' "$SETTINGS_FILE" 2>/dev/null)

        if [[ -n "$status_type" ]]; then
            echo "  Type:    $status_type"
            echo "  Command: $status_cmd"
            echo "  Padding: $status_padding"

            # Check if pointing to this plugin
            if [[ "$status_cmd" == "$STATUSLINE_SCRIPT" ]]; then
                echo -e "  ${GREEN}✓ Points to this plugin${RESET}"
            else
                echo -e "  ${YELLOW}⚠ Points to different script${RESET}"
            fi
        else
            echo -e "  ${YELLOW}No statusLine configured${RESET}"
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
