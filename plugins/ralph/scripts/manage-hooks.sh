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

# UV executable path - detected during install from common locations
# This is validated to fail loudly if UV is not available
UV_PATH=""

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

# Detect UV from common installation locations
# Sets UV_PATH to the first valid UV executable found
# Returns 0 if found, 1 if not found
detect_uv() {
    # Check locations in priority order (most common first)
    local uv_locations=(
        "$HOME/.local/share/mise/shims/uv"      # mise (most common for Claude users)
        "$HOME/.local/bin/uv"                    # uv installer default
        "/opt/homebrew/bin/uv"                   # Homebrew on Apple Silicon
        "/usr/local/bin/uv"                      # Homebrew on Intel / manual install
        "$HOME/.cargo/bin/uv"                    # cargo install
    )

    for loc in "${uv_locations[@]}"; do
        if [[ -x "$loc" ]]; then
            UV_PATH="$loc"
            return 0
        fi
    done

    return 1
}

# Validate UV is available - fail loudly with helpful instructions
# Sets UV_VERSION on success
UV_VERSION=""
MIN_UV_VERSION="0.5.0"  # Minimum version for PEP 723 script support

validate_uv() {
    if ! detect_uv; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "ERROR: UV executable not found"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "Ralph hooks require UV to run Python scripts."
        echo "Searched locations:"
        echo "  - \$HOME/.local/share/mise/shims/uv  (mise)"
        echo "  - \$HOME/.local/bin/uv              (uv installer)"
        echo "  - /opt/homebrew/bin/uv              (Homebrew)"
        echo "  - /usr/local/bin/uv                 (manual)"
        echo "  - \$HOME/.cargo/bin/uv              (cargo)"
        echo ""
        echo "Install UV via one of these methods:"
        echo "  • curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "  • brew install uv"
        echo "  • mise use -g uv@latest"
        echo ""
        die "UV is required but not found. See instructions above."
    fi

    # Validate UV actually works and get version
    local version_output
    if ! version_output=$("$UV_PATH" --version 2>&1); then
        die "UV found at $UV_PATH but failed to execute. Check installation."
    fi

    # Extract version number (e.g., "uv 0.9.21 (abc123)" -> "0.9.21")
    UV_VERSION=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    # Version comparison using sort -V
    if [[ -n "$UV_VERSION" ]]; then
        local older_version
        older_version=$(printf '%s\n%s' "$MIN_UV_VERSION" "$UV_VERSION" | sort -V | head -1)
        if [[ "$older_version" != "$MIN_UV_VERSION" ]]; then
            echo ""
            warn "UV version $UV_VERSION is below minimum $MIN_UV_VERSION"
            echo "  Upgrade with: uv self update"
            echo "  Or: curl -LsSf https://astral.sh/uv/install.sh | sh"
            echo ""
        fi
    fi
}

validate_json() {
    local file="$1"
    local jq_error
    if ! jq_error=$(jq empty "$file" 2>&1); then
        echo "[ralph] JSON validation failed: $jq_error" >&2
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
    if ! mkdir -p "$BACKUP_DIR" 2>&1; then
        echo "[ralph] Failed to create backup directory: $BACKUP_DIR" >&2
        return 1
    fi
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/settings.json.backup.$timestamp"
    if ! cp "$SETTINGS" "$backup_file" 2>&1; then
        echo "[ralph] Failed to create backup: $backup_file" >&2
        return 1
    fi
    echo "$timestamp"
}

is_installed() {
    # Check if any hook command contains the marker
    jq -e '.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))' "$SETTINGS" >/dev/null 2>&1
}

count_hooks() {
    local count
    local jq_error
    if ! count=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>&1); then
        echo "[ralph] Failed to count hooks: $count" >&2
        echo "0"
        return 1
    fi
    echo "$count"
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
        local hooks_list
        if ! hooks_list=$(jq -r '.hooks | to_entries[] | select(.value[] | .hooks[] | .command | contains("'"$MARKER"'")) | "  - \(.key)"' "$SETTINGS" 2>&1); then
            echo "[ralph] Failed to list hooks: $hooks_list" >&2
        else
            echo "$hooks_list" | sort -u
        fi
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
    validate_uv  # Detect and validate UV - fails loudly if not found

    # Idempotency check
    if is_installed; then
        warn "ralph hooks are already installed. Use 'uninstall' first to reinstall."
        do_status
        return 0
    fi

    # Verify hook scripts exist
    local stop_script="$HOOKS_BASE/loop-until-done.py"
    local pretooluse_archive_script="$HOOKS_BASE/archive-plan.sh"
    local pretooluse_guard_script="$HOOKS_BASE/pretooluse-loop-guard.py"

    if [[ ! -f "$stop_script" ]]; then
        die "Stop hook script not found: $stop_script"
    fi
    if [[ ! -f "$pretooluse_archive_script" ]]; then
        die "PreToolUse archive hook script not found: $pretooluse_archive_script"
    fi
    if [[ ! -f "$pretooluse_guard_script" ]]; then
        die "PreToolUse loop guard script not found: $pretooluse_guard_script"
    fi

    # Create backup
    local timestamp
    timestamp=$(create_backup)
    info "Created backup: settings.json.backup.$timestamp"

    # Build hook command paths using detected PLUGIN_ROOT and UV_PATH
    # Convert absolute paths to $HOME-based for portability in settings.json
    local home_relative="${PLUGIN_ROOT/#$HOME/\$HOME}"
    local uv_cmd="${UV_PATH/#$HOME/\$HOME}"
    local stop_cmd="${uv_cmd} run ${home_relative}/hooks/loop-until-done.py"
    local pretooluse_archive_cmd="${home_relative}/hooks/archive-plan.sh"
    local pretooluse_guard_cmd="${uv_cmd} run ${home_relative}/hooks/pretooluse-loop-guard.py"

    # Prepare hook entries using jq for proper JSON escaping
    # Structure: each entry is added to the event array directly
    # Stop: {"hooks": [{type, command, timeout}]}
    # PreToolUse: {"matcher": "...", "hooks": [{type, command, timeout}]}
    local stop_entry
    local pretooluse_archive_entry
    local pretooluse_guard_entry
    if ! stop_entry=$(jq -n --arg cmd "$stop_cmd" '{"hooks":[{"type":"command","command":$cmd,"timeout":30000}]}' 2>&1); then
        die "Failed to create Stop hook entry: $stop_entry"
    fi
    # NOTE: PreToolUse entry should NOT have outer {"hooks": [...]} wrapper
    # The matcher and hooks are at the same level in the array element
    if ! pretooluse_archive_entry=$(jq -n --arg cmd "$pretooluse_archive_cmd" '{"matcher":"Write|Edit","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}' 2>&1); then
        die "Failed to create PreToolUse archive hook entry: $pretooluse_archive_entry"
    fi
    # Bash guard hook - protects loop control files from deletion
    if ! pretooluse_guard_entry=$(jq -n --arg cmd "$pretooluse_guard_cmd" '{"matcher":"Bash","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}' 2>&1); then
        die "Failed to create PreToolUse guard hook entry: $pretooluse_guard_entry"
    fi

    # Create temp file for atomic write
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Apply modifications using jq
    local jq_result
    if ! jq_result=$(jq --argjson stop "$stop_entry" --argjson preArchive "$pretooluse_archive_entry" --argjson preGuard "$pretooluse_guard_entry" '
        .hooks //= {} |
        .hooks.Stop //= [] |
        .hooks.Stop += [$stop] |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse += [$preArchive, $preGuard]
    ' "$SETTINGS" 2>&1); then
        die "Failed to modify settings.json: $jq_result"
    fi
    echo "$jq_result" > "$temp_file"

    # Validate the new JSON
    if ! validate_json "$temp_file"; then
        die "Generated invalid JSON. Aborting. Original file unchanged."
    fi

    # Atomic move
    if ! mv "$temp_file" "$SETTINGS" 2>&1; then
        die "Failed to write settings.json"
    fi
    trap - EXIT

    # Record installation timestamp for restart detection
    if ! date +%s > "$INSTALL_TIMESTAMP_FILE" 2>&1; then
        echo "[ralph] Warning: Failed to record install timestamp" >&2
    fi

    info "ralph hooks installed successfully!"
    echo ""
    echo "Plugin root: $PLUGIN_ROOT"
    echo "UV detected: $UV_PATH (v$UV_VERSION)"
    echo ""
    echo "Hooks installed:"
    echo "  - Stop: loop-until-done.py (autonomous loop control)"
    echo "      Convergence detection, task completion monitoring, exploration pivoting"
    echo "  - PreToolUse (Write|Edit): archive-plan.sh (plan file archival)"
    echo "      Preserves investigation history before plan modifications"
    echo "  - PreToolUse (Bash): pretooluse-loop-guard.py (loop file protection)"
    echo "      Guards loop control files, allows official Ralph command bypass"
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
    local jq_result
    if ! jq_result=$(jq '
        .hooks |= (
            to_entries | map(
                .value |= map(
                    select(.hooks | all(.command | contains("'"$MARKER"'") | not))
                )
            ) | from_entries
        )
    ' "$SETTINGS" 2>&1); then
        die "Failed to modify settings.json: $jq_result"
    fi
    echo "$jq_result" > "$temp_file"

    # Validate the new JSON
    if ! validate_json "$temp_file"; then
        die "Generated invalid JSON. Aborting. Original file unchanged."
    fi

    # Atomic move
    if ! mv "$temp_file" "$SETTINGS" 2>&1; then
        die "Failed to write settings.json"
    fi
    trap - EXIT

    # Clean up global Ralph files
    if [[ -f "$INSTALL_TIMESTAMP_FILE" ]]; then
        if ! rm "$INSTALL_TIMESTAMP_FILE" 2>&1; then
            echo "[ralph] Warning: Failed to remove install timestamp" >&2
        else
            info "Removed install timestamp file"
        fi
    fi

    # Remove stop reason cache (stale after uninstall)
    local stop_reason_file="$HOME/.claude/ralph-stop-reason.json"
    if [[ -f "$stop_reason_file" ]]; then
        if ! rm "$stop_reason_file" 2>&1; then
            echo "[ralph] Warning: Failed to remove stop reason cache" >&2
        else
            info "Removed stop reason cache"
        fi
    fi

    info "ralph hooks uninstalled successfully!"
    echo ""
    echo "Note: Session history and logs preserved in ~/.claude/automation/loop-orchestrator/state/"
    echo "      Project config preserved in .claude/loop-config.json"
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
