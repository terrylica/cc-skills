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
# COMMAND PATTERN CHECK
# ============================================================================
COMMAND="${TOOL_INPUT_COMMAND:-}"

# Only check if command contains gh CLI calls
if ! echo "$COMMAND" | grep -qE '\bgh\s+'; then
    exit 0
fi

# EXEMPT: auth/config/completion commands (Major fix for gh auth login lockout)
if echo "$COMMAND" | grep -qE '\bgh\s+(auth|config|completion)\b'; then
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
    deny_with_reason "[gh-isolation] BLOCKED: GH_CONFIG_DIR not set in Claude's environment.

PROBLEM: GitHub commands blocked - multi-account isolation not active. The gh CLI would use ~/.config/gh/ which may contain wrong account credentials.

ROOT CAUSE: Claude Code was launched from a shell without mise environment loaded.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"GitHub account isolation is not configured. How would you like to proceed?\",
    \"header\": \"GitHub\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Restart Claude Code (Recommended)\", \"description\": \"Exit and relaunch from a terminal with mise activated\"},
      {\"label\": \"Activate mise now\", \"description\": \"Run: source <(mise hook-env -s bash) in terminal, then restart Claude Code\"},
      {\"label\": \"Skip isolation\", \"description\": \"Set GH_ISOLATION_FORCE_ALLOW=true to bypass (may use wrong account)\"}
    ]
  }]
}"
fi

# ============================================================================
# VALIDATE PROFILE EXISTS
# ============================================================================
if [[ ! -f "${GH_CONFIG_DIR}/hosts.yml" ]]; then
    deny_with_reason "[gh-isolation] BLOCKED: GitHub profile not initialized.

PROBLEM: GH_CONFIG_DIR=${GH_CONFIG_DIR} exists but hosts.yml is missing. The isolated profile has never been authenticated.

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

PROBLEM: gh CLI authenticated as '${ACTIVE_USER}' but directory expects '${GH_ACCOUNT}'. Wrong account would create issues/PRs under wrong identity.

ACTION REQUIRED: You MUST call the AskUserQuestion tool (not just print text). Use these exact parameters:

{
  \"questions\": [{
    \"question\": \"Wrong GitHub account (${ACTIVE_USER}) is active. Expected: ${GH_ACCOUNT}. How to fix?\",
    \"header\": \"Account\",
    \"multiSelect\": false,
    \"options\": [
      {\"label\": \"Switch account (Recommended)\", \"description\": \"Run: gh auth switch --user ${GH_ACCOUNT}\"},
      {\"label\": \"Re-authenticate\", \"description\": \"Run: gh auth login (select ${GH_ACCOUNT})\"},
      {\"label\": \"Use current account\", \"description\": \"Set GH_ISOLATION_FORCE_ALLOW=true (will use ${ACTIVE_USER})\"}
    ]
  }]
}"
    fi
fi

# All good - GH_CONFIG_DIR isolation is active and account matches
exit 0
