#!/usr/bin/env bash
# sred-commit-guard.sh - Claude Code PreToolUse hook for SR&ED commit enforcement
# PROCESS-STORM-OK: "trailer" refers to git trailers, not fork bombs
#
# Validates commits include BOTH conventional commit type AND SR&ED git trailers.
# Can also be called from git commit-msg hook for dual-layer enforcement.
#
# Usage:
#   PreToolUse: Piped JSON with tool_input.command containing git commit
#   Git hook:   ./sred-commit-guard.sh --git-hook "$1"
#
# Exit codes:
#   0 - Valid or non-commit command (allow)
#   JSON output with permissionDecision:deny - Block with reason

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Conventional commit types (standard)
CONVENTIONAL_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

# SR&ED types for CRA claims
SRED_TYPES="experimental-development|applied-research|basic-research|systematic-investigation"

# Required metadata (set to "true" to require)
REQUIRE_SRED_TYPE="true"
REQUIRE_SRED_CLAIM="false"  # Optional but recommended

# ============================================================================
# INPUT PARSING
# ============================================================================

if [[ "${1:-}" == "--git-hook" ]]; then
    # Git commit-msg hook mode
    MODE="git"
    COMMIT_MSG_FILE="${2:-.git/COMMIT_EDITMSG}"
    if [[ ! -f "$COMMIT_MSG_FILE" ]]; then
        echo "ERROR: Commit message file not found: $COMMIT_MSG_FILE" >&2
        exit 1
    fi
    COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")
else
    # Claude Code PreToolUse mode
    MODE="claude"
    INPUT=$(cat)

    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""

    # Only intercept Bash tool
    if [[ "$TOOL_NAME" != "Bash" ]]; then
        exit 0
    fi

    # Only intercept git commit commands
    if ! echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
        exit 0
    fi

    # Block --no-verify attempts
    if echo "$COMMAND" | grep -qE -- '--no-verify|-n\b'; then
        jq -n --arg reason "[SRED-COMMIT-GUARD] BLOCKED: --no-verify bypasses commit validation.

Remove the --no-verify flag. SR&ED claim compliance requires validated commits." \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
        exit 0
    fi

    # Extract commit message from -m flag
    # Handle: -m "message", -m 'message', -m "$(cat <<'EOF'\nmessage\nEOF\n)"
    if echo "$COMMAND" | grep -qE -- '-m\s'; then
        # Try to extract message - handles heredoc and simple quotes
        COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*-m [\"']\\([^\"']*\\)[\"'].*/\\1/p" | head -1)

        # If empty, try heredoc extraction
        if [[ -z "$COMMIT_MSG" ]]; then
            COMMIT_MSG=$(echo "$COMMAND" | sed -n "s/.*-m \"\$(cat <<'EOF'//p" | head -1)
        fi

        # If still empty, might be using editor - allow
        if [[ -z "$COMMIT_MSG" ]]; then
            exit 0
        fi
    else
        # No -m flag, using editor - allow (git commit-msg hook will validate)
        exit 0
    fi
fi

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

ERRORS=()

validate_conventional_type() {
    local msg="$1"
    local first_line
    first_line=$(echo "$msg" | head -n1)

    if ! echo "$first_line" | grep -qE "^($CONVENTIONAL_TYPES)(\(.+\))?: .+"; then
        ERRORS+=("Missing or invalid conventional commit type. Expected: feat|fix|docs|test|perf|refactor|chore|ci|build")
    fi
}

validate_sred_type_metadata() {
    local msg="$1"

    if [[ "$REQUIRE_SRED_TYPE" != "true" ]]; then
        return 0
    fi

    # Check for SRED-Type in git metadata format
    if ! echo "$msg" | grep -qE "^SRED-Type:\s*($SRED_TYPES)"; then
        ERRORS+=("Missing SRED-Type metadata. Required for SR&ED claim compliance.

Add one of:
  SRED-Type: experimental-development
  SRED-Type: applied-research
  SRED-Type: basic-research
  SRED-Type: systematic-investigation")
    fi
}

validate_sred_claim_metadata() {
    local msg="$1"

    if [[ "$REQUIRE_SRED_CLAIM" != "true" ]]; then
        return 0
    fi

    # Check for SRED-Claim metadata
    if ! echo "$msg" | grep -qE "^SRED-Claim:\s*.+"; then
        ERRORS+=("Missing SRED-Claim metadata. Add: SRED-Claim: <claim-id>")
    fi
}

# ============================================================================
# RUN VALIDATIONS
# ============================================================================

validate_conventional_type "$COMMIT_MSG"
validate_sred_type_metadata "$COMMIT_MSG"
validate_sred_claim_metadata "$COMMIT_MSG"

# ============================================================================
# OUTPUT RESULTS
# ============================================================================

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    ERROR_MSG="[SRED-COMMIT-GUARD] Commit message validation failed:

"
    for err in "${ERRORS[@]}"; do
        ERROR_MSG+="- $err
"
    done

    ERROR_MSG+="
Required format:
\`\`\`
<type>(<scope>): <description>

<body>

SRED-Type: <category>
SRED-Claim: <claim-id>  (optional)
\`\`\`

Example:
\`\`\`
feat(ith-python): implement adaptive TMAEG threshold

Adds volatility-regime-aware threshold adjustment for ITH epoch detection.

SRED-Type: experimental-development
SRED-Claim: 2026-Q1-ITH
\`\`\`"

    if [[ "$MODE" == "claude" ]]; then
        jq -n --arg reason "$ERROR_MSG" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    else
        echo "$ERROR_MSG" >&2
        exit 1
    fi
    exit 0
fi

# Valid - allow commit
if [[ "$MODE" == "git" ]]; then
    echo "[SRED-COMMIT-GUARD] Commit message valid."
fi
exit 0
