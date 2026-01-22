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

# Hook script always exits 0 (process success), but outputs decision:"block" to
# prevent Claude from stopping until link violations are fixed (hard-blocking behavior).
# This ensures Claude sees and acts on violations before session ends.
# Use set -u for unbound variable checking, but no -e or pipefail
set -u

# Verbose error logging for Claude Code CLI
log_error() {
    echo "[lychee-stop-hook] ERROR: $*" >&2
}

log_debug() {
    # Uncomment for debugging: echo "[lychee-stop-hook] DEBUG: $*" >&2
    :
}

# === Configuration ===
HOOK_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools}"
LINT_SCRIPT="${HOOK_ROOT}/scripts/lint-relative-paths"

# Read JSON payload from stdin (Claude Code provides hook context)
PAYLOAD=$(cat 2>/dev/null || echo '{}')

# Check stop_hook_active - if true, user is forcing stop, allow it
STOP_HOOK_ACTIVE=$(echo "$PAYLOAD" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0  # User forcing stop, skip validation
fi

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
    # KEY IMPROVEMENT: Use git ls-files to respect .gitignore
    # This eliminates false positives from cloned repos (repos/), build artifacts (target/), etc.
    MD_FILES_TMP=$(mktemp)

    # Try git ls-files first (respects .gitignore)
    if git -C "$GIT_ROOT" ls-files --cached '*.md' '**/*.md' 2>/dev/null | head -100 > "$MD_FILES_TMP" && [[ -s "$MD_FILES_TMP" ]]; then
        log_debug "Using git ls-files (respects .gitignore)"
        # Prepend GIT_ROOT to each path for absolute paths
        if ! sed -i.bak "s|^|${GIT_ROOT}/|" "$MD_FILES_TMP" 2>/dev/null; then
            # BSD sed doesn't support -i without backup, use portable approach
            if ! sed "s|^|${GIT_ROOT}/|" "$MD_FILES_TMP" > "${MD_FILES_TMP}.new"; then
                log_error "sed failed to prepend paths"
            elif ! mv "${MD_FILES_TMP}.new" "$MD_FILES_TMP"; then
                log_error "mv failed when updating temp file"
            fi
        fi
        rm -f "${MD_FILES_TMP}.bak" 2>/dev/null || true  # Cleanup, failure ok
    else
        # Fallback: find with expanded exclusion list
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
            -not -path "*/repos/*" \
            -not -path "*/target/*" \
            -not -path "*/vendor/*" \
            -not -path "*/dist/*" \
            -not -path "*/build/*" \
            -not -path "*/out/*" \
            -not -path "*/coverage/*" \
            -not -path "*/__pycache__/*" \
            2>/dev/null | head -100 > "$MD_FILES_TMP"
    fi

    if [[ -s "$MD_FILES_TMP" ]]; then
        # Run lychee on files (use temp file for output too)
        # --root-dir: Required to resolve root-relative paths like /docs/foo.md
        # --config: Use project .lychee.toml if it exists (excludes test fixtures, etc.)
        LYCHEE_TMP=$(mktemp)
        # Build lychee command args as array to avoid SC2086
        LYCHEE_ARGS=(--offline --no-progress --format json --root-dir "$GIT_ROOT")
        if [[ -f "$GIT_ROOT/.lychee.toml" ]]; then
            LYCHEE_ARGS+=(--config "$GIT_ROOT/.lychee.toml")
        fi
        if xargs lychee "${LYCHEE_ARGS[@]}" < "$MD_FILES_TMP" > "$LYCHEE_TMP" 2>/dev/null; then
            # Count only REAL errors, not path resolution errors
            # Path resolution errors have url="error:" (lychee can't parse the path)
            # Real errors have actual URLs (file:// or https://) - missing files, 404s, etc.
            LYCHEE_ERRORS=$(jq '[.error_map | .[]? | .[]? | select(.url != "error:")] | length' "$LYCHEE_TMP" 2>/dev/null || echo 0)
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
# IMPORTANT: Stop hooks have different schema than PreToolUse/PostToolUse!
# Stop hooks do NOT support hookSpecificOutput. Valid Stop hook fields:
# - continue: boolean (optional) - whether to allow stop
# - suppressOutput: boolean (optional)
# - stopReason: string (optional)
# - decision: "block" + reason - BLOCKS stopping AND injects reason into Claude context
# - systemMessage: string (optional) - UI-only, Claude does NOT see this!
#
# CRITICAL INSIGHT: systemMessage is UI-only (shown to user, not to Claude).
# To make Claude SEE and ACT on violations, we must use decision:"block" + reason.
# This blocks stopping AND injects the reason into Claude's conversation context.
TOTAL_ISSUES=$((${LYCHEE_ERRORS:-0} + ${PATH_VIOLATIONS:-0}))

if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
    # Build detailed message with actual violations
    MSG="[LINK VALIDATION] Found $TOTAL_ISSUES issue(s) that must be fixed before stopping:\n\n"

    # Include lychee errors if any
    if [[ "${LYCHEE_ERRORS:-0}" -gt 0 ]] && [[ -f "$LYCHEE_CACHE" ]]; then
        MSG+="=== Lychee Link Errors (${LYCHEE_ERRORS}) ===\n"
        # Extract failed links from lychee JSON
        LYCHEE_DETAILS=$(jq -r '.fail[]? | "- \(.url) in \(.source)"' "$LYCHEE_CACHE" 2>/dev/null | head -20)
        if [[ -n "$LYCHEE_DETAILS" ]]; then
            MSG+="$LYCHEE_DETAILS\n"
        fi
        MSG+="\n"
    fi

    # Include path violations with full details
    if [[ "${PATH_VIOLATIONS:-0}" -gt 0 ]] && [[ -f "$LINT_CACHE" ]]; then
        MSG+="=== Path Violations (${PATH_VIOLATIONS}) ===\n"
        # Include the actual violation report (limit to 50 lines)
        LINT_DETAILS=$(cat "$LINT_CACHE" | head -50)
        MSG+="$LINT_DETAILS\n"
    fi

    MSG+="\nFix these markdown link issues, then the session can end cleanly."

    # Use decision:"block" + reason to:
    # 1. BLOCK stopping (force Claude to continue)
    # 2. INJECT reason into Claude's context (so Claude can see and fix issues)
    # This is different from systemMessage which is UI-only!
    printf '%s' "$MSG" | jq -Rs '{decision: "block", reason: .}'
fi

# Always exit 0 (non-blocking hook)
exit 0
