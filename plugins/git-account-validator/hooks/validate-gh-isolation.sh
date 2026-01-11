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

WHAT HAPPENED: This gh command was blocked because multi-account GitHub isolation is not active. Without GH_CONFIG_DIR, the gh CLI uses ~/.config/gh/ which may contain the wrong account credentials.

ROOT CAUSE: Claude Code was launched from a shell where mise environment variables were not loaded.

WHAT CLAUDE SHOULD DO:
1. Inform the user that GitHub commands are blocked due to missing account isolation
2. Ask the user to restart Claude Code from a properly configured shell
3. The user should run: source <(mise hook-env -s bash) OR restart their terminal (if mise is in shell rc file)
4. After restart, GH_CONFIG_DIR and GH_ACCOUNT will be inherited by Claude Code

TEMPORARY BYPASS: Set GH_ISOLATION_FORCE_ALLOW=true (not recommended - may use wrong account)"
fi

# ============================================================================
# VALIDATE PROFILE EXISTS
# ============================================================================
if [[ ! -f "${GH_CONFIG_DIR}/hosts.yml" ]]; then
    deny_with_reason "[gh-isolation] BLOCKED: GitHub profile not initialized.

WHAT HAPPENED: GH_CONFIG_DIR is set to ${GH_CONFIG_DIR} but no hosts.yml exists. This means the isolated profile has never been authenticated.

WHAT CLAUDE SHOULD DO:
1. Inform the user that the GitHub profile needs to be initialized
2. The user should run: GH_CONFIG_DIR='${GH_CONFIG_DIR}' gh auth login
3. After authentication, retry the original gh command

TEMPORARY BYPASS: Set GH_ISOLATION_FORCE_ALLOW=true (not recommended)"
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

WHAT HAPPENED: The gh CLI is authenticated as '${ACTIVE_USER}' but this directory expects '${GH_ACCOUNT}'. Using the wrong account would create issues/PRs under the wrong identity.

WHAT CLAUDE SHOULD DO:
1. Inform the user that the wrong GitHub account is active
2. The user should run: gh auth switch --user ${GH_ACCOUNT}
3. If that fails, the user may need to: gh auth login (and select ${GH_ACCOUNT})
4. After switching, retry the original gh command

TEMPORARY BYPASS: Set GH_ISOLATION_FORCE_ALLOW=true (not recommended - will use wrong account)"
    fi
fi

# All good - GH_CONFIG_DIR isolation is active and account matches
exit 0
