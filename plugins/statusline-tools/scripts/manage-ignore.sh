#!/usr/bin/env bash
# manage-ignore.sh - Manage global ignore patterns for lint-relative-paths
#
# MIT License
# Copyright (c) 2025 Terry Li
#
# Usage:
#   manage-ignore.sh add <pattern>    Add a pattern to the ignore file
#   manage-ignore.sh list             List current patterns
#   manage-ignore.sh remove <pattern> Remove a pattern from the ignore file
#
# Ignore file location: ~/.claude/lint-relative-paths-ignore
# Pattern matching: substring match (path contains pattern)

set -euo pipefail

# === Configuration ===
IGNORE_FILE="${HOME}/.claude/lint-relative-paths-ignore"

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

# Ensure ignore file exists with header
ensure_ignore_file() {
    if [[ ! -f "$IGNORE_FILE" ]]; then
        log_info "Creating $IGNORE_FILE"
        mkdir -p "$(dirname "$IGNORE_FILE")"
        cat > "$IGNORE_FILE" << 'EOF'
# Global ignore patterns for lint-relative-paths
# Lines starting with # are comments
# Patterns use substring matching (workspace path contains pattern)

EOF
        log_success "Created ignore file with header"
    fi
}

# === Commands ===

cmd_add() {
    local pattern="${1:-}"

    if [[ -z "$pattern" ]]; then
        log_error "Usage: manage-ignore.sh add <pattern>"
        log_info "Example: manage-ignore.sh add alpha-forge"
        exit 1
    fi

    ensure_ignore_file

    # Check if pattern already exists
    if grep -qxF "$pattern" "$IGNORE_FILE" 2>/dev/null; then
        log_warn "Pattern already exists: $pattern"
        return 0
    fi

    # Add pattern
    echo "$pattern" >> "$IGNORE_FILE"
    log_success "Added pattern: $pattern"
    log_info "Workspaces containing '$pattern' in their path will skip relative path linting"
}

cmd_list() {
    echo -e "${CYAN}=== Global Ignore Patterns ===${RESET}"
    echo ""
    echo -e "${CYAN}File:${RESET} $IGNORE_FILE"
    echo ""

    if [[ ! -f "$IGNORE_FILE" ]]; then
        echo -e "${YELLOW}No ignore file found.${RESET}"
        echo ""
        echo "Create one with: /statusline-tools:ignore add <pattern>"
        return 0
    fi

    echo -e "${CYAN}Patterns:${RESET}"
    local has_patterns=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Show comments in yellow, patterns in green
        if [[ "$line" == \#* ]]; then
            echo -e "  ${YELLOW}$line${RESET}"
        else
            echo -e "  ${GREEN}• $line${RESET}"
            has_patterns=true
        fi
    done < "$IGNORE_FILE"

    if [[ "$has_patterns" == false ]]; then
        echo -e "  ${YELLOW}(no patterns defined)${RESET}"
    fi

    echo ""
    echo -e "${CYAN}Usage:${RESET}"
    echo "  Patterns use substring matching."
    echo "  A workspace path containing the pattern will skip linting."
}

cmd_remove() {
    local pattern="${1:-}"

    if [[ -z "$pattern" ]]; then
        log_error "Usage: manage-ignore.sh remove <pattern>"
        log_info "Example: manage-ignore.sh remove alpha-forge"
        exit 1
    fi

    if [[ ! -f "$IGNORE_FILE" ]]; then
        log_error "No ignore file found at $IGNORE_FILE"
        exit 1
    fi

    # Check if pattern exists
    if ! grep -qxF "$pattern" "$IGNORE_FILE" 2>/dev/null; then
        log_error "Pattern not found: $pattern"
        log_info "Current patterns:"
        grep -v '^#' "$IGNORE_FILE" 2>/dev/null | grep -v '^$' | while read -r p; do
            echo "  • $p"
        done
        exit 1
    fi

    # Remove pattern (using temp file for safety)
    local tmp_file
    tmp_file=$(mktemp)
    grep -vxF "$pattern" "$IGNORE_FILE" > "$tmp_file"
    mv "$tmp_file" "$IGNORE_FILE"

    log_success "Removed pattern: $pattern"
}

# === Main ===

usage() {
    echo "Usage: $(basename "$0") [add|list|remove] [pattern]"
    echo ""
    echo "Commands:"
    echo "  add <pattern>     Add a pattern to the global ignore file"
    echo "  list              List current patterns"
    echo "  remove <pattern>  Remove a pattern from the ignore file"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") add alpha-forge"
    echo "  $(basename "$0") list"
    echo "  $(basename "$0") remove alpha-forge"
    exit 1
}

main() {
    local command="${1:-}"
    local pattern="${2:-}"

    case "$command" in
        add)
            cmd_add "$pattern"
            ;;
        list)
            cmd_list
            ;;
        remove)
            cmd_remove "$pattern"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
