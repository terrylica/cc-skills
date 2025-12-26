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

# Non-blocking hook - must always exit 0
# Use set -u for unbound variable checking, but no -e or pipefail
set -u

# === Configuration ===
HOOK_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
LINT_SCRIPT="${HOOK_ROOT}/scripts/lint-relative-paths"

# Read JSON payload from stdin (Claude Code provides hook context)
PAYLOAD=$(cat 2>/dev/null || echo '{}')

# Extract workspace directory
WORKSPACE=$(echo "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || echo "")
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE=$(pwd)
fi

# Change to workspace
cd "$WORKSPACE" 2>/dev/null || exit 0

# Check if we're in a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# === Lychee Link Validation ===
LYCHEE_CACHE="${GIT_ROOT}/.lychee-results.json"
LYCHEE_ERRORS=0
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if command -v lychee &>/dev/null; then
    # Find markdown files (exclude caches, plugins, backups)
    # Use temp file to avoid pipeline issues
    MD_FILES_TMP=$(mktemp)
    find "$GIT_ROOT" -type f -name "*.md" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -not -path "*/tmp/*" \
        -not -path "*/archive/*" \
        -not -path "*/plugins/cache/*" \
        -not -path "*/plugins/marketplaces/*" \
        -not -path "*/backups/*" \
        -not -path "*/staging/*" \
        2>/dev/null | head -100 > "$MD_FILES_TMP"

    if [[ -s "$MD_FILES_TMP" ]]; then
        # Run lychee on files (use temp file for output too)
        LYCHEE_TMP=$(mktemp)
        if xargs lychee --offline --no-progress --format json < "$MD_FILES_TMP" > "$LYCHEE_TMP" 2>/dev/null; then
            LYCHEE_ERRORS=$(jq -r '.errors // 0' "$LYCHEE_TMP" 2>/dev/null || echo 0)
        fi
        rm -f "$LYCHEE_TMP"
    fi
    rm -f "$MD_FILES_TMP"

    # Write cache file
    echo "{\"errors\": ${LYCHEE_ERRORS:-0}, \"timestamp\": \"$TIMESTAMP\"}" > "$LYCHEE_CACHE"
else
    # lychee not installed
    echo "{\"errors\": 0, \"warning\": \"lychee not installed\", \"timestamp\": \"$TIMESTAMP\"}" > "$LYCHEE_CACHE"
fi

# === lint-relative-paths Validation ===
LINT_CACHE="${GIT_ROOT}/.lint-relative-paths-results.txt"
PATH_VIOLATIONS=0

if [[ -x "$LINT_SCRIPT" ]]; then
    LINT_OUTPUT=$("$LINT_SCRIPT" "$GIT_ROOT" 2>&1 || true)
    echo "$LINT_OUTPUT" > "$LINT_CACHE"
    PATH_VIOLATIONS=$(echo "$LINT_OUTPUT" | grep -oE 'Found [0-9]+ violation' | grep -oE '[0-9]+' || echo 0)
elif [[ -x "$HOME/.claude/bin/lint-relative-paths" ]]; then
    LINT_OUTPUT=$("$HOME/.claude/bin/lint-relative-paths" "$GIT_ROOT" 2>&1 || true)
    echo "$LINT_OUTPUT" > "$LINT_CACHE"
    PATH_VIOLATIONS=$(echo "$LINT_OUTPUT" | grep -oE 'Found [0-9]+ violation' | grep -oE '[0-9]+' || echo 0)
else
    echo "lint-relative-paths not found" > "$LINT_CACHE"
fi

# === Report Summary ===
# IMPORTANT: Stop hooks have different semantics than PostToolUse!
# - decision: "block" = ACTUALLY PREVENTS Claude from stopping (forces continuation)
# - hookSpecificOutput.additionalContext = Informs Claude without blocking
#
# This hook is INFORMATIONAL, not blocking. We want Claude to see the info
# but still allow the session to end. Use additionalContext for this.
TOTAL_ISSUES=$((${LYCHEE_ERRORS:-0} + ${PATH_VIOLATIONS:-0}))

if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
    # Use additionalContext for Stop hooks - visible to Claude but non-blocking
    jq -n \
        --arg ctx "[LINK VALIDATION] Session ended with $TOTAL_ISSUES issue(s): Lychee errors: ${LYCHEE_ERRORS:-0}, Path violations: ${PATH_VIOLATIONS:-0}. Check .lychee-results.json and .lint-relative-paths-results.txt in repo root." \
        '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $ctx}}'
fi

# Always exit 0 (non-blocking hook)
exit 0
