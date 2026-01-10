#!/usr/bin/env bash
# Hook: validate-gh-isolation.sh
# Triggers: PreToolUse on Bash commands containing "gh "
# Purpose: Ensure GH_CONFIG_DIR isolation is active before gh commands
# NOTE: This script is GENERIC - no usernames hardcoded.
#       All account info comes from environment variables set by mise.

set -euo pipefail

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
# LOAD MISE ENVIRONMENT (Critical: hooks don't inherit mise env)
# ============================================================================
if [[ -z "${GH_CONFIG_DIR:-}" ]] && command -v mise &>/dev/null; then
    eval "$(mise hook-env -s bash 2>/dev/null)" || true
fi

# ============================================================================
# VALIDATE GH_CONFIG_DIR IS SET
# ============================================================================
if [[ -z "${GH_CONFIG_DIR:-}" ]]; then
    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════════════╗" >&2
    echo "║  ⚠️  GH_CONFIG_DIR isolation NOT configured for this directory       ║" >&2
    echo "╠══════════════════════════════════════════════════════════════════════╣" >&2
    echo "║  The gh CLI uses global ~/.config/gh/ config by default, which       ║" >&2
    echo "║  shares the active account across ALL directories.                   ║" >&2
    echo "║                                                                       ║" >&2
    echo "║  For multi-account GitHub workflows, set in your .mise.toml:         ║" >&2
    echo "║    [env]                                                              ║" >&2
    echo '║    GH_CONFIG_DIR = "{{ env.HOME }}/.config/gh-profiles/<account>"    ║' >&2
    echo "║    GH_ACCOUNT = \"<account>\"                                         ║" >&2
    echo "║                                                                       ║" >&2
    echo "║  To bypass temporarily: GH_ISOLATION_FORCE_ALLOW=true                ║" >&2
    echo "╚══════════════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    echo "SUGGESTION_FOR_CLAUDE: Ask user if they want help setting up GH_CONFIG_DIR isolation for multi-account GitHub."
    exit 2
fi

# ============================================================================
# VALIDATE PROFILE EXISTS
# ============================================================================
if [[ ! -f "${GH_CONFIG_DIR}/hosts.yml" ]]; then
    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════════════╗" >&2
    echo "║  ⚠️  GH_CONFIG_DIR set but profile not initialized                   ║" >&2
    echo "╠══════════════════════════════════════════════════════════════════════╣" >&2
    echo "║  GH_CONFIG_DIR=${GH_CONFIG_DIR}" >&2
    echo "║  But hosts.yml does not exist in that directory.                     ║" >&2
    echo "║                                                                       ║" >&2
    echo "║  Run: gh auth login   (will create hosts.yml in GH_CONFIG_DIR)       ║" >&2
    echo "║                                                                       ║" >&2
    echo "║  To bypass temporarily: GH_ISOLATION_FORCE_ALLOW=true                ║" >&2
    echo "╚══════════════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    echo "SUGGESTION_FOR_CLAUDE: Ask user if they want to run 'gh auth login' to initialize the profile."
    exit 2
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
        echo "" >&2
        echo "╔══════════════════════════════════════════════════════════════════════╗" >&2
        echo "║  ⚠️  Active gh account doesn't match expected GH_ACCOUNT             ║" >&2
        echo "╠══════════════════════════════════════════════════════════════════════╣" >&2
        echo "║  Expected: ${GH_ACCOUNT}" >&2
        echo "║  Active:   ${ACTIVE_USER}" >&2
        echo "║                                                                       ║" >&2
        echo "║  The gh profile has a different user as active.                      ║" >&2
        echo "║                                                                       ║" >&2
        echo "║  Fix: gh auth switch --user ${GH_ACCOUNT}                            ║" >&2
        echo "║                                                                       ║" >&2
        echo "║  To bypass temporarily: GH_ISOLATION_FORCE_ALLOW=true                ║" >&2
        echo "╚══════════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        echo "SUGGESTION_FOR_CLAUDE: Run 'gh auth switch --user ${GH_ACCOUNT}' to fix the active account mismatch."
        exit 2
    fi
fi

# All good - GH_CONFIG_DIR isolation is active and account matches
exit 0
