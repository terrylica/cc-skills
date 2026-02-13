#!/usr/bin/env bash
# manage-hooks.sh - Idempotent productivity-tools hooks installer for settings.json
#
# Usage: manage-hooks.sh [install|uninstall|status]
#
# Design principles:
# - Idempotent: safe to run multiple times
# - Atomic: uses temp file + mv to prevent corruption
# - Validated: checks JSON validity before committing
# - Path-agnostic: auto-detects marketplace, cache, or dev paths

set -euo pipefail

# === Configuration ===
SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="productivity-tools/hooks/"  # Unique identifier in command paths

# Auto-detect plugin root with fallback chain
detect_plugin_root() {
    # Priority 1: Environment variable
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi

    # Priority 2: Marketplace path (local dev)
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/productivity-tools"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi

    # Priority 3: Cache path (GitHub install - latest version)
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/productivity-tools"
    if [[ -d "$cache_base" ]]; then
        local latest
        latest=$(cd "$cache_base" && printf '%s\n' [0-9]*.[0-9]* 2>/dev/null | sort -V | tail -1)
        if [[ -n "$latest" && -d "$cache_base/$latest/hooks" ]]; then
            echo "$cache_base/$latest"
            return
        fi
    fi

    # Priority 4: Relative to script (ultimate fallback)
    dirname "$SCRIPT_DIR"
}

PLUGIN_ROOT="$(detect_plugin_root)"
HOOKS_BASE="$PLUGIN_ROOT/hooks"

# === Colors for output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Check if hooks are already installed
is_installed() {
    if [[ ! -f "$SETTINGS" ]]; then
        return 1
    fi
    jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("'"$MARKER"'"))' "$SETTINGS" &>/dev/null
}

# Create backup of settings.json
backup_settings() {
    if [[ ! -f "$SETTINGS" ]]; then
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.backup.$ts"
    info "Backed up to: $BACKUP_DIR/settings.json.backup.$ts"
}

# Validate JSON
validate_json() {
    local file="$1"
    if ! jq empty "$file" 2>/dev/null; then
        die "Invalid JSON in $file"
    fi
}

# === Main Actions ===

do_status() {
    echo -e "${CYAN}=== productivity-tools Hooks Status ===${NC}"
    echo ""

    # Plugin location
    echo -e "${CYAN}Plugin Location:${NC}"
    if [[ -n "$PLUGIN_ROOT" && -d "$PLUGIN_ROOT" ]]; then
        echo -e "  ${GREEN}✓${NC} $PLUGIN_ROOT"
    else
        echo -e "  ${RED}✗${NC} Plugin not found"
    fi
    echo ""

    # Dependency check
    echo -e "${CYAN}Dependencies:${NC}"
    if command -v jq &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} jq $(jq --version 2>/dev/null | head -1)"
    else
        echo -e "  ${RED}✗${NC} jq - REQUIRED. Install: brew install jq"
    fi
    if command -v bun &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} bun $(bun --version 2>/dev/null | head -1)"
    else
        echo -e "  ${RED}✗${NC} bun - REQUIRED for calendar hook. Install: brew install bun"
    fi
    echo ""

    # Hook script check
    echo -e "${CYAN}Hook Scripts:${NC}"
    local hook_script="$HOOKS_BASE/calendar-reminder-sync.ts"
    if [[ -f "$hook_script" ]]; then
        if [[ -x "$hook_script" ]]; then
            echo -e "  ${GREEN}✓${NC} calendar-reminder-sync.ts"
        else
            echo -e "  ${YELLOW}⚠${NC} calendar-reminder-sync.ts (not executable)"
        fi
    else
        echo -e "  ${RED}✗${NC} calendar-reminder-sync.ts - NOT FOUND"
    fi
    echo ""

    # Registration check
    echo -e "${CYAN}Hook Registration:${NC}"
    if is_installed; then
        echo -e "  ${GREEN}✓${NC} Installed in settings.json"
    else
        echo -e "  ${CYAN}○${NC} Not installed"
        echo -e "      Run: /productivity-tools:hooks install"
    fi
    echo ""
}

do_install() {
    # Check jq
    command -v jq &>/dev/null || die "jq is required. Install: brew install jq"

    # Check bun
    command -v bun &>/dev/null || die "bun is required for calendar hook. Install: brew install bun"

    # Check hook script exists
    local hook_script="$HOOKS_BASE/calendar-reminder-sync.ts"
    [[ -f "$hook_script" ]] || die "Hook script not found: $hook_script"

    # Check if already installed
    if is_installed; then
        info "productivity-tools hooks already installed (idempotent)"
        return 0
    fi

    # Backup
    backup_settings

    # Initialize settings if needed
    if [[ ! -f "$SETTINGS" ]]; then
        echo '{}' > "$SETTINGS"
    fi

    # Build hook entry (use $HOME for path expansion at runtime)
    local hook_path="\$HOME/.claude/plugins/marketplaces/cc-skills/plugins/productivity-tools/hooks/calendar-reminder-sync.ts"
    local hook_entry
    hook_entry=$(jq -n --arg cmd "bun $hook_path" '{
        matcher: "Bash",
        hooks: [{
            type: "command",
            command: $cmd,
            timeout: 10000
        }]
    }')

    # Add to settings.json
    local tmp
    tmp=$(mktemp)

    # Ensure hooks.PostToolUse exists and add our entry
    jq --argjson calendar "$hook_entry" '
        .hooks //= {} |
        .hooks.PostToolUse //= [] |
        .hooks.PostToolUse += [$calendar]
    ' "$SETTINGS" > "$tmp"

    # Validate before committing
    validate_json "$tmp"

    # Atomic write
    mv "$tmp" "$SETTINGS"

    info "productivity-tools hooks installed successfully (1 hook)"
    echo "  - PostToolUse/Bash: calendar-reminder-sync.ts"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Restart Claude Code for hooks to take effect."
    echo ""
}

do_uninstall() {
    command -v jq &>/dev/null || die "jq is required. Install: brew install jq"

    if ! is_installed; then
        info "productivity-tools hooks not installed (nothing to do)"
        return 0
    fi

    # Backup
    backup_settings

    # Remove productivity-tools hooks
    local tmp
    tmp=$(mktemp)

    jq '
        .hooks.PostToolUse //= [] |
        .hooks.PostToolUse = [.hooks.PostToolUse[] | select(.hooks[]?.command | contains("'"$MARKER"'") | not)]
    ' "$SETTINGS" > "$tmp"

    # Validate before committing
    validate_json "$tmp"

    # Atomic write
    mv "$tmp" "$SETTINGS"

    info "productivity-tools hooks uninstalled successfully"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Restart Claude Code for changes to take effect."
    echo ""
}

# === Main ===

ACTION="${1:-status}"

case "$ACTION" in
    status)
        do_status
        ;;
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    *)
        echo "Usage: manage-hooks.sh [install|uninstall|status]"
        exit 1
        ;;
esac
