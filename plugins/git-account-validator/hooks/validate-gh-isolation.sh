#!/usr/bin/env bash
# Hook: validate-gh-isolation.sh
# Triggers: PreToolUse on Bash commands containing "gh "
# Purpose: Ensure GH_CONFIG_DIR isolation is active before gh commands
# NOTE: This script is GENERIC - no usernames hardcoded.
#       All account info comes from environment variables set by mise.
#
# Output Format (PreToolUse): JSON with hookSpecificOutput per lifecycle-reference.md
# Reference: plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md

set -euo pipefail

# Helper function: Output PreToolUse deny with reason (Claude receives this)
deny_with_reason() {
    local reason="$1"
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
    exit 0  # Exit 0 with JSON, not exit 2
}

# ============================================================================
# RECURSION GUARD (Critical fix for circular dependency)
# ============================================================================
if [[ "${_GH_ISOLATION_HOOK_ACTIVE:-0}" == "1" ]]; then
    exit 0  # Skip nested hook invocation
fi
export _GH_ISOLATION_HOOK_ACTIVE=1
trap 'unset _GH_ISOLATION_HOOK_ACTIVE' EXIT

# ============================================================================
# BYPASS MECHANISM (Minor fix for emergency override)
# ============================================================================
if [[ "${GH_ISOLATION_FORCE_ALLOW:-false}" == "true" ]]; then
    echo "⚠️  [gh-isolation] GH_ISOLATION_FORCE_ALLOW=true - bypassing validation" >&2
    exit 0
fi

# ============================================================================
# INPUT PARSING (Required - hooks receive JSON via stdin, NOT env vars)
# ============================================================================
# Reference: https://claude.com/blog/how-to-configure-hooks
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
# CWD available in INPUT if needed: jq -r '.cwd // ""'

# ============================================================================
# COMMAND PATTERN CHECK
# ============================================================================

# Only check if command contains gh CLI calls as actual commands
# Must handle: "gh issue list", "cd foo && gh pr", but NOT "git commit -m 'gh CLI'"
# Strategy: Check if first word of any command segment is "gh"
CONTAINS_GH_COMMAND=false

# Robust detection: extract first word of each command segment
# 1. Replace shell operators with newlines to split into segments
# 2. Check if any segment starts with "gh " (the actual command)
# NOTE: Don't strip quotes - that causes false positives with heredocs/$(...)
# Instead, split by operators and check first word of each segment
COMMAND_SEGMENTS=$(echo "$COMMAND" | tr ';&|' '\n')
while IFS= read -r segment; do
    # Trim leading whitespace and get first word
    segment_trimmed="${segment#"${segment%%[![:space:]]*}"}"
    first_word="${segment_trimmed%% *}"
    if [[ "$first_word" == "gh" ]]; then
        CONTAINS_GH_COMMAND=true
        break
    fi
done <<< "$COMMAND_SEGMENTS"

if [[ "$CONTAINS_GH_COMMAND" != "true" ]]; then
    exit 0
fi

# EXEMPT: auth/config/completion commands (Major fix for gh auth login lockout)
if echo "$COMMAND" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+(auth|config|completion)\b'; then
    exit 0  # Allow authentication and config commands unconditionally
fi

# ============================================================================
# VALIDATE GH_CONFIG_DIR IS SET (No self-healing!)
# ============================================================================
# CRITICAL: We must NOT load mise env here. The hook runs in a subprocess,
# but the actual `gh` command runs in Claude's environment which does NOT
# have mise env loaded. If we self-heal here, validation passes but the
# actual command still uses wrong account.
#
# The fix: DENY if GH_CONFIG_DIR is not already set. This forces the user
# to configure their shell/mise properly so Claude inherits the env vars.
# ============================================================================
if [[ -z "${GH_CONFIG_DIR:-}" ]]; then
    # Try to detect expected account from mise config for better UX
    # Use sed for macOS compatibility (grep -P not available)
    EXPECTED_ACCOUNT=""
    if [[ -f ".mise.toml" ]]; then
        EXPECTED_ACCOUNT=$(grep 'GH_ACCOUNT' .mise.toml 2>/dev/null | sed -E 's/.*GH_ACCOUNT[[:space:]]*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)
    fi
    if [[ -z "$EXPECTED_ACCOUNT" ]] && [[ -f ".mise.local.toml" ]]; then
        EXPECTED_ACCOUNT=$(grep 'GH_ACCOUNT' .mise.local.toml 2>/dev/null | sed -E 's/.*GH_ACCOUNT[[:space:]]*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)
    fi

    # Also try to get current gh user for context
    CURRENT_GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")

    if [[ -n "$EXPECTED_ACCOUNT" ]]; then
        deny_with_reason "[gh-isolation] BLOCKED: GH_CONFIG_DIR not set in Claude's environment.

PROBLEM: Only \`gh\` CLI commands are blocked. Current gh user: '${CURRENT_GH_USER}'. Expected for this directory: '${EXPECTED_ACCOUNT}'.

NOTE: Other Bash commands (git, chezmoi, npm, etc.) work normally. Only GitHub CLI (\`gh\`) commands require isolation.

ROOT CAUSE: Claude Code was launched from a shell without mise environment loaded.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"GitHub account isolation not active. This directory expects '${EXPECTED_ACCOUNT}' but gh CLI may use '${CURRENT_GH_USER}'. Which account do you want to use?\",
    \"header\": \"Account\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Use ${EXPECTED_ACCOUNT} (Recommended)\", \"description\": \"Restart Claude Code from terminal with mise activated to use ${EXPECTED_ACCOUNT}\"},
      {\"label\": \"Use ${CURRENT_GH_USER} anyway\", \"description\": \"Set GH_ISOLATION_FORCE_ALLOW=true to proceed with current account\"},
      {\"label\": \"Use different account\", \"description\": \"Specify which GitHub account you want to use for this directory\"}
    ]
  }]
}"
    else
        deny_with_reason "[gh-isolation] BLOCKED: GH_CONFIG_DIR not set in Claude's environment.

PROBLEM: Only \`gh\` CLI commands are blocked. Current gh user: '${CURRENT_GH_USER}'. No GH_ACCOUNT configured in mise for this directory.

NOTE: Other Bash commands (git, chezmoi, npm, etc.) work normally. Only GitHub CLI (\`gh\`) commands require isolation.

ROOT CAUSE: Claude Code was launched from a shell without mise environment loaded.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"GitHub account isolation not active. Current gh CLI user is '${CURRENT_GH_USER}'. Which account should be used for this directory?\",
    \"header\": \"Account\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Use ${CURRENT_GH_USER}\", \"description\": \"Set GH_ISOLATION_FORCE_ALLOW=true to proceed with current account\"},
      {\"label\": \"Configure isolation first\", \"description\": \"Set up GH_ACCOUNT in .mise.toml, then restart Claude Code\"},
      {\"label\": \"Use different account\", \"description\": \"Specify which GitHub account you want to use for this directory\"}
    ]
  }]
}"
    fi
fi

# ============================================================================
# VALIDATE PROFILE EXISTS
# ============================================================================
if [[ ! -f "${GH_CONFIG_DIR}/hosts.yml" ]]; then
    deny_with_reason "[gh-isolation] BLOCKED: GitHub profile not initialized.

PROBLEM: Only \`gh\` CLI commands are blocked. GH_CONFIG_DIR=${GH_CONFIG_DIR} exists but hosts.yml is missing.

NOTE: Other Bash commands (git, chezmoi, npm, etc.) work normally. Only GitHub CLI (\`gh\`) commands require isolation.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"GitHub profile needs authentication. How would you like to proceed?\",
    \"header\": \"Auth\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Authenticate now (Recommended)\", \"description\": \"Run: GH_CONFIG_DIR='${GH_CONFIG_DIR}' gh auth login\"},
      {\"label\": \"Skip isolation\", \"description\": \"Set GH_ISOLATION_FORCE_ALLOW=true to bypass (not recommended)\"}
    ]
  }]
}"
fi

# ============================================================================
# VALIDATE ACTIVE ACCOUNT MATCHES GH_ACCOUNT (if set)
# ============================================================================
# The gh CLI has its own "active account" concept per profile.
# Even with correct GH_CONFIG_DIR, the wrong user might be active.
# Fixes: https://github.com/terrylica/cc-skills/issues/4
if [[ -n "${GH_ACCOUNT:-}" ]]; then
    # Query active account (uses cached token, fast)
    ACTIVE_USER=$(GH_CONFIG_DIR="$GH_CONFIG_DIR" gh api user --jq '.login' 2>/dev/null || echo "")

    if [[ -n "$ACTIVE_USER" && "$ACTIVE_USER" != "$GH_ACCOUNT" ]]; then
        deny_with_reason "[gh-isolation] BLOCKED: Wrong GitHub account active.

PROBLEM: Only \`gh\` CLI commands are blocked. Current: '${ACTIVE_USER}', expected: '${GH_ACCOUNT}'.

NOTE: Other Bash commands (git, chezmoi, npm, etc.) work normally. Only GitHub CLI (\`gh\`) commands require isolation.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"Account mismatch: gh CLI is '${ACTIVE_USER}' but directory expects '${GH_ACCOUNT}'. Which account do you want to use?\",
    \"header\": \"Account\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Use ${GH_ACCOUNT} (Recommended)\", \"description\": \"Switch to expected account: gh auth switch --user ${GH_ACCOUNT}\"},
      {\"label\": \"Use ${ACTIVE_USER} instead\", \"description\": \"Keep current account and set GH_ISOLATION_FORCE_ALLOW=true\"},
      {\"label\": \"Use different account\", \"description\": \"Specify another GitHub account to use for this directory\"}
    ]
  }]
}"
    fi
fi

# All good - GH_CONFIG_DIR isolation is active and account matches
exit 0
