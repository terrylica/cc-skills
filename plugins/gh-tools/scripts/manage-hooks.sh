#!/usr/bin/env bash
# manage-hooks.sh - Idempotent gh-tools hooks installer for settings.json
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
MARKER="gh-tools/hooks/"  # Unique identifier in command paths

# Auto-detect plugin root with fallback chain
detect_plugin_root() {
    # Priority 1: Environment variable
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi

    # Priority 2: Marketplace path (local dev)
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gh-tools"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi

    # Priority 3: Cache path (GitHub install - latest version)
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/gh-tools"
    if [[ -d "$cache_base" ]]; then
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
    jq -e '.hooks.PreToolUse[]? | select(.hooks[]?.command | contains("'"$MARKER"'"))' "$SETTINGS" &>/dev/null
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
    echo -e "${CYAN}=== gh-tools Hooks Status ===${NC}"
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
    echo ""

    # Hook script check
    echo -e "${CYAN}Hook Scripts:${NC}"
    local hook_script="$HOOKS_BASE/webfetch-github-guard.sh"
    if [[ -f "$hook_script" ]]; then
        if [[ -x "$hook_script" ]]; then
            echo -e "  ${GREEN}✓${NC} webfetch-github-guard.sh"
        else
            echo -e "  ${YELLOW}⚠${NC} webfetch-github-guard.sh (not executable)"
        fi
    else
        echo -e "  ${RED}✗${NC} webfetch-github-guard.sh - NOT FOUND"
    fi

    local issue_hook="$HOOKS_BASE/gh-issue-body-file-guard.mjs"
    if [[ -f "$issue_hook" ]]; then
        if [[ -x "$issue_hook" ]]; then
            echo -e "  ${GREEN}✓${NC} gh-issue-body-file-guard.mjs"
        else
            echo -e "  ${YELLOW}⚠${NC} gh-issue-body-file-guard.mjs (not executable)"
        fi
    else
        echo -e "  ${RED}✗${NC} gh-issue-body-file-guard.mjs - NOT FOUND"
    fi
    echo ""

    # Registration check
    echo -e "${CYAN}Hook Registration:${NC}"
    if is_installed; then
        echo -e "  ${GREEN}✓${NC} Installed in settings.json"
    else
        echo -e "  ${CYAN}○${NC} Not installed"
        echo -e "      Run: /gh-tools:hooks install"
    fi
    echo ""
}

do_install() {
    # Check jq
    command -v jq &>/dev/null || die "jq is required. Install: brew install jq"

    # Check hook scripts exist
    local webfetch_hook="$HOOKS_BASE/webfetch-github-guard.sh"
    local issue_hook="$HOOKS_BASE/gh-issue-body-file-guard.mjs"
    [[ -f "$webfetch_hook" ]] || die "Hook script not found: $webfetch_hook"
    [[ -f "$issue_hook" ]] || die "Hook script not found: $issue_hook"

    # Check if already installed
    if is_installed; then
        info "gh-tools hooks already installed (idempotent)"
        return 0
    fi

    # Backup
    backup_settings

    # Initialize settings if needed
    if [[ ! -f "$SETTINGS" ]]; then
        echo '{}' > "$SETTINGS"
    fi

    # Build hook entries (use $HOME for path expansion at runtime)
    local webfetch_path="\$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gh-tools/hooks/webfetch-github-guard.sh"
    local webfetch_entry
    webfetch_entry=$(jq -n --arg cmd "$webfetch_path" '{
        matcher: "WebFetch",
        hooks: [{
            type: "command",
            command: $cmd,
            timeout: 5000
        }]
    }')

    local issue_path="\$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gh-tools/hooks/gh-issue-body-file-guard.mjs"
    local issue_entry
    issue_entry=$(jq -n --arg cmd "$issue_path" '{
        matcher: "Bash",
        hooks: [{
            type: "command",
            command: $cmd,
            timeout: 5000
        }]
    }')

    # Add to settings.json
    local tmp
    tmp=$(mktemp)

    # Ensure hooks.PreToolUse exists and add our entries
    jq --argjson webfetch "$webfetch_entry" --argjson issue "$issue_entry" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [$webfetch, $issue]
    ' "$SETTINGS" > "$tmp"

    # Validate before committing
    validate_json "$tmp"

    # Atomic write
    mv "$tmp" "$SETTINGS"

    info "gh-tools hooks installed successfully (2 hooks)"
    echo "  - WebFetch: webfetch-github-guard.sh"
    echo "  - Bash: gh-issue-body-file-guard.mjs"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Restart Claude Code for hooks to take effect."
    echo ""
}

do_uninstall() {
    command -v jq &>/dev/null || die "jq is required. Install: brew install jq"

    if ! is_installed; then
        info "gh-tools hooks not installed (nothing to do)"
        return 0
    fi

    # Backup
    backup_settings

    # Remove gh-tools hooks
    local tmp
    tmp=$(mktemp)

    jq '
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks[]?.command | contains("'"$MARKER"'") | not)]
    ' "$SETTINGS" > "$tmp"

    # Validate before committing
    validate_json "$tmp"

    # Atomic write
    mv "$tmp" "$SETTINGS"

    info "gh-tools hooks uninstalled successfully"
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
