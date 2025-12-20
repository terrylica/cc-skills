#!/usr/bin/env bash
# lychee-stop-hook.sh - Simplified Stop hook for link validation
#
# MIT License
# Copyright (c) 2025 Terry Li
#
# This hook runs on Claude Code session stop to:
# 1. Validate markdown links using lychee
# 2. Check for relative path violations using lint-relative-paths
# 3. Write cache files for status line to display
#
# Output files:
#   .lychee-results.json - Link validation results (errors count)
#   .lint-relative-paths-results.txt - Path violation report
#
# Dependencies:
#   - lychee (optional - graceful degradation if missing)
#   - lint-relative-paths (bundled with plugin)
#   - jq (required)

set -euo pipefail

# === Configuration ===
HOOK_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
LINT_SCRIPT="${HOOK_ROOT}/scripts/lint-relative-paths"

# Read JSON payload from stdin (Claude Code provides hook context)
PAYLOAD=$(cat)

# Extract workspace directory
WORKSPACE=$(echo "$PAYLOAD" | jq -r '.cwd // empty')
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE=$(pwd)
fi

# Change to workspace
cd "$WORKSPACE" || exit 0

# Check if we're in a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    # Not in a git repo - nothing to validate
    exit 0
}

# === Lychee Link Validation ===
LYCHEE_CACHE="${GIT_ROOT}/.lychee-results.json"
LYCHEE_ERRORS=0

if command -v lychee &>/dev/null; then
    # Find markdown files
    MD_FILES=$(find "$GIT_ROOT" -type f -name "*.md" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -not -path "*/tmp/*" \
        -not -path "*/archive/*" \
        2>/dev/null | head -500)

    if [[ -n "$MD_FILES" ]]; then
        # Run lychee in offline mode (no network requests)
        # Output JSON format for easy parsing
        LYCHEE_OUTPUT=$(echo "$MD_FILES" | xargs lychee \
            --offline \
            --no-progress \
            --format json \
            2>/dev/null) || true

        if [[ -n "$LYCHEE_OUTPUT" ]]; then
            # Extract error count from lychee JSON output
            LYCHEE_ERRORS=$(echo "$LYCHEE_OUTPUT" | jq -r '.fail_map | length // 0' 2>/dev/null || echo 0)

            # Write cache file
            echo "{\"errors\": $LYCHEE_ERRORS, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$LYCHEE_CACHE"
        else
            # No output - assume clean
            echo '{"errors": 0, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$LYCHEE_CACHE"
        fi
    else
        # No markdown files - clean result
        echo '{"errors": 0, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$LYCHEE_CACHE"
    fi
else
    # lychee not installed - write empty cache with warning
    echo '{"errors": 0, "warning": "lychee not installed", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$LYCHEE_CACHE"
fi

# === lint-relative-paths Validation ===
LINT_CACHE="${GIT_ROOT}/.lint-relative-paths-results.txt"
PATH_VIOLATIONS=0

if [[ -x "$LINT_SCRIPT" ]]; then
    # Run lint-relative-paths and capture output
    LINT_OUTPUT=$("$LINT_SCRIPT" "$GIT_ROOT" 2>&1) || true

    # Write results to cache
    echo "$LINT_OUTPUT" > "$LINT_CACHE"

    # Extract violation count
    PATH_VIOLATIONS=$(echo "$LINT_OUTPUT" | grep -oE 'Found [0-9]+ violation' | grep -oE '[0-9]+' || echo 0)
elif [[ -x "$HOME/.claude/bin/lint-relative-paths" ]]; then
    # Fallback to global installation
    LINT_OUTPUT=$("$HOME/.claude/bin/lint-relative-paths" "$GIT_ROOT" 2>&1) || true
    echo "$LINT_OUTPUT" > "$LINT_CACHE"
    PATH_VIOLATIONS=$(echo "$LINT_OUTPUT" | grep -oE 'Found [0-9]+ violation' | grep -oE '[0-9]+' || echo 0)
else
    # lint-relative-paths not found
    echo "lint-relative-paths not found" > "$LINT_CACHE"
fi

# === Report Summary ===
TOTAL_ISSUES=$((LYCHEE_ERRORS + PATH_VIOLATIONS))

if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
    # Output summary for Claude to see (non-blocking)
    echo "[LINK VALIDATION] Found issues: L:${LYCHEE_ERRORS} P:${PATH_VIOLATIONS}"
fi

# Always exit 0 (non-blocking hook)
exit 0
