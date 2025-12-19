#!/usr/bin/env bash
# manage-hooks.sh - Idempotent git-account-validator hooks installer
#
# Usage: manage-hooks.sh [install|uninstall|status]

set -euo pipefail

# === Configuration ===
SETTINGS="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
HOOKS_BASE="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/git-account-validator/hooks"
MARKER="git-account-validator/hooks/"

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

die() { echo -e "${RED}ERROR:${NC} $1" >&2; exit 1; }
info() { echo -e "${GREEN}INFO:${NC} $1"; }
warn() { echo -e "${YELLOW}WARN:${NC} $1"; }

check_dependencies() {
    command -v jq &>/dev/null || die "jq is required. Install: brew install jq"
}

validate_json() { jq empty "$1" 2>/dev/null; }

ensure_settings_exists() {
    [[ -f "$SETTINGS" ]] || die "Settings not found: $SETTINGS"
    validate_json "$SETTINGS" || die "Invalid JSON: $SETTINGS"
}

create_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts=$(date +%Y%m%d_%H%M%S)
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.backup.$ts"
    echo "$ts"
}

is_installed() {
    jq -e '.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))' "$SETTINGS" >/dev/null 2>&1
}

count_hooks() {
    jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0"
}

do_status() {
    ensure_settings_exists
    local count=$(count_hooks)
    if [[ "$count" -gt 0 ]]; then
        info "git-account-validator hooks are INSTALLED ($count hook entries)"
        jq -r '.hooks | to_entries[] | select(.value[] | .hooks[] | .command | contains("'"$MARKER"'")) | "  - \(.key)"' "$SETTINGS" | sort -u
    else
        info "git-account-validator hooks are NOT installed"
        echo "To install: /git-account-validator:hooks install"
        return 1
    fi
}

do_install() {
    ensure_settings_exists
    check_dependencies

    is_installed && { warn "Already installed. Use 'uninstall' first."; do_status; return 0; }

    [[ -x "$HOOKS_BASE/validate-git-push.sh" ]] || die "Script not found: $HOOKS_BASE/validate-git-push.sh"

    local ts=$(create_backup)
    info "Backup: settings.json.backup.$ts"

    local pre_entry='{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/git-account-validator/hooks/validate-git-push.sh","timeout":15}]}'

    local temp=$(mktemp)
    trap 'rm -f "$temp"' EXIT

    jq --argjson pre "$pre_entry" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [$pre]
    ' "$SETTINGS" > "$temp"

    validate_json "$temp" || die "Generated invalid JSON"
    mv "$temp" "$SETTINGS"
    trap - EXIT

    info "git-account-validator hook installed!"
    echo "  - PreToolUse: validate-git-push.sh (validates git push for multi-account auth)"
    echo ""
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
}

do_uninstall() {
    ensure_settings_exists
    check_dependencies

    is_installed || { warn "Not installed."; return 0; }

    local ts=$(create_backup)
    info "Backup: settings.json.backup.$ts"

    local temp=$(mktemp)
    trap 'rm -f "$temp"' EXIT

    jq '
        .hooks |= (to_entries | map(.value |= map(select(.hooks | all(.command | contains("'"$MARKER"'") | not)))) | from_entries)
    ' "$SETTINGS" > "$temp"

    validate_json "$temp" || die "Generated invalid JSON"
    mv "$temp" "$SETTINGS"
    trap - EXIT

    info "git-account-validator hooks uninstalled!"
    echo "IMPORTANT: Restart Claude Code for changes to take effect."
}

case "${1:-status}" in
    install) do_install ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    *) die "Unknown: $1. Use: install|uninstall|status" ;;
esac
