#!/usr/bin/env bash
#
# PreToolUse hook: Validate GitHub account before git push
#
# Hard blocks (exit 2) when:
# 1. Remote URL is HTTPS (requires SSH for multi-account support)
# 2. SSH would authenticate as wrong account
#
# Architecture: Uses git config credential.username (from includeIf) as source of truth,
# then validates SSH auth matches. Bypasses ControlMaster caching with -o ControlMaster=no.
#
# Design principles:
# - All user-facing output to STDOUT (Claude sees stdout, not stderr)
# - Cross-platform (macOS + Linux)
# - Graceful degradation when dependencies missing
# - No hardcoded private information
#
# ADR: [Future - document when created]

# Don't use set -e to allow graceful error handling
set -uo pipefail

#=============================================================================
# Utility Functions
#=============================================================================

# Cross-platform timeout command (macOS uses gtimeout from coreutils)
timeout_cmd() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$@"
    else
        # Fallback: run without timeout (risky but better than failing)
        shift  # Remove timeout value
        "$@"
    fi
}

# Output to stdout (visible to Claude in additionalContext)
log_info() {
    echo "$@"
}

# Output to BOTH stdout AND stderr (for blocking messages)
# - stderr: Claude Code UI displays this when hook exits with code 2
# - stdout: Goes to additionalContext for Claude's conversation context
log_error() {
    echo "$@" >&2
    echo "$@"
}

# Output block header to BOTH streams
log_block() {
    local msg="$1"
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════" >&2
    echo "$msg" >&2
    echo "═══════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    # Also to stdout for Claude context
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "$msg"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
}

#=============================================================================
# Dependency Checks
#=============================================================================

# Check for jq (required for JSON parsing)
if ! command -v jq &>/dev/null; then
    log_info "⚠️  [git-account-validator] jq not found - skipping validation"
    log_info "   Install: brew install jq (macOS) or apt install jq (Linux)"
    exit 0
fi

#=============================================================================
# Input Parsing
#=============================================================================

# Read JSON from stdin
INPUT=$(cat)

# Extract fields with error handling
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""

# Only intercept Bash tool with git push commands
if [[ "$TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

# Check for git push (handle various forms: git push, git push origin, git push -u, etc.)
if ! echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
    exit 0
fi

# Detect chained commands (git add && git commit && git push)
# These are risky because earlier commands succeed even if push fails
IS_CHAINED_COMMAND=false
if echo "$COMMAND" | grep -qE '&&|;|\|'; then
    IS_CHAINED_COMMAND=true
fi

#=============================================================================
# Context Validation
#=============================================================================

# Change to working directory for git commands
if ! cd "$CWD" 2>/dev/null; then
    log_info "⚠️  [git-account-validator] Cannot cd to $CWD - skipping validation"
    exit 0
fi

# Check if this is a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0  # Not a git repo, allow
fi

#=============================================================================
# Step 1: Get Remote URL
#=============================================================================

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

if [[ -z "$REMOTE_URL" ]]; then
    log_info "⚠️  [git-account-validator] No origin remote found - skipping validation"
    exit 0
fi

#=============================================================================
# Step 2: Block HTTPS URLs (output to STDOUT so Claude sees it)
#=============================================================================

if [[ "$REMOTE_URL" =~ ^https:// ]]; then
    log_block "BLOCKED: HTTPS remote URL detected"
    log_error "Current URL: $REMOTE_URL"
    log_error ""
    log_error "HTTPS URLs bypass SSH multi-account configuration and can push"
    log_error "to the wrong account. Please switch to SSH:"
    log_error ""

    # Extract owner/repo from HTTPS URL and suggest fix
    if [[ "$REMOTE_URL" =~ github\.com[/:]([^/]+)/([^/.]+) ]]; then
        OWNER="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]}"
        log_error "Run: git remote set-url origin git@github.com:${OWNER}/${REPO}.git"
    fi
    log_error ""
    exit 2
fi

#=============================================================================
# Step 3: Get Expected Username from Git Config
#=============================================================================

# This uses includeIf to get the correct username for the current directory
EXPECTED_USER=$(git config credential.username 2>/dev/null || echo "")

if [[ -z "$EXPECTED_USER" ]]; then
    log_info ""
    log_info "⚠️  [git-account-validator] No credential.username in git config"
    log_info ""
    log_info "Cannot determine expected GitHub account for: $CWD"
    log_info ""
    log_info "Fix: Add includeIf directive to ~/.gitconfig, e.g.:"
    log_info '  [includeIf "gitdir:/path/to/repos/"]'
    log_info '      path = ~/.gitconfig-<account>'
    log_info ""
    log_info "Where ~/.gitconfig-<account> contains:"
    log_info "  [credential]"
    log_info "      username = <your-github-username>"
    log_info ""
    exit 0  # Can't validate without expected user
fi

#=============================================================================
# Step 4: Validate SSH Authentication
#=============================================================================

# Configurable timeout (default 5 seconds, override with GIT_ACCOUNT_VALIDATOR_TIMEOUT)
SSH_TIMEOUT="${GIT_ACCOUNT_VALIDATOR_TIMEOUT:-5}"

# Pre-flush: Close any cached ControlMaster connections to GitHub
# This prevents stale authentication from being reused
# Silent failures are OK - connection may not exist
ssh -O exit git@github.com 2>/dev/null || true
ssh -O exit -p 443 git@ssh.github.com 2>/dev/null || true

# Also close connections for common host aliases (pattern: github.com-*)
for control_socket in ~/.ssh/control-git@github.com* ~/.ssh/control-git@ssh.github.com*; do
    if [[ -S "$control_socket" ]]; then
        # Extract host from socket name and close it
        ssh -O exit -o ControlPath="$control_socket" git@github.com 2>/dev/null || true
    fi
done

# Bypass ControlMaster cache to get fresh authentication result
# Try standard port 22 first, fallback to port 443 (ssh.github.com) if blocked
SSH_OUTPUT=$(timeout_cmd "$SSH_TIMEOUT" ssh -o ControlMaster=no -o BatchMode=yes -T git@github.com 2>&1 || true)

# If port 22 is blocked, try port 443 fallback (GitHub offers SSH via ssh.github.com:443)
if echo "$SSH_OUTPUT" | grep -qiE 'connection refused|connection timed out'; then
    SSH_OUTPUT_443=$(timeout_cmd "$SSH_TIMEOUT" ssh -o ControlMaster=no -o BatchMode=yes -p 443 -T git@ssh.github.com 2>&1 || true)
    if [[ "$SSH_OUTPUT_443" =~ Hi\ ([^!]+)! ]]; then
        # Port 443 succeeded - use this result
        SSH_OUTPUT="$SSH_OUTPUT_443"
        log_info "ℹ️  Port 22 blocked, validated via port 443 (ssh.github.com)"
    fi
fi

# Extract authenticated username from SSH response
# GitHub responds with: "Hi <username>! You've successfully authenticated..."
if [[ "$SSH_OUTPUT" =~ Hi\ ([^!]+)! ]]; then
    SSH_USER="${BASH_REMATCH[1]}"
else
    # SSH validation failed - determine if this is a NETWORK issue or AUTH issue
    # Network issues: warn only (push will fail naturally)
    # Auth issues: could mean wrong account - warn strongly but don't block

    # NEW DESIGN: Default to warn-only for network issues
    # Only block on explicit account mismatch (handled in Step 5)
    # Rationale: Network timeouts will cause git push to fail anyway,
    # blocking just adds frustration. The hook's primary value is
    # catching account mismatches, not network connectivity issues.

    # Allow strict mode override for users who want blocking behavior
    STRICT_MODE="${GIT_ACCOUNT_VALIDATOR_STRICT:-false}"  # Default changed to false

    if [[ "$STRICT_MODE" == "true" ]]; then
        log_block "BLOCKED: SSH validation failed (strict mode)"
        log_error "SSH output: $SSH_OUTPUT"
        log_error ""
        log_error "Expected account: $EXPECTED_USER"
        log_error ""
        log_error "To disable strict mode: export GIT_ACCOUNT_VALIDATOR_STRICT=false"
        log_error ""
        exit 2
    else
        # WARN-ONLY: Network issues shouldn't block the command
        log_info ""
        log_info "⚠️  [git-account-validator] SSH validation inconclusive"
        log_info ""
        log_info "Cannot verify GitHub account (likely network issue)."
        log_info "Expected account: $EXPECTED_USER"
        log_info ""

        # Helpful diagnostics if SSH output indicates specific issue
        if [[ -z "$SSH_OUTPUT" ]] || echo "$SSH_OUTPUT" | grep -qiE 'timed out|timeout'; then
            log_info "Hint: Try flushing DNS cache:"
            log_info "  sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
            log_info ""
        fi

        log_info "Proceeding - git push will fail naturally if network is down."
        log_info ""
        exit 0  # ALLOW - let git push handle network errors
    fi
fi

#=============================================================================
# Step 5: Compare Accounts (output to STDOUT so Claude sees it)
#=============================================================================

if [[ "$SSH_USER" != "$EXPECTED_USER" ]]; then
    log_block "BLOCKED: GitHub account mismatch detected"
    log_error "Directory:     $CWD"
    log_error "Expected user: $EXPECTED_USER (from git config)"
    log_error "SSH auth user: $SSH_USER"
    log_error ""
    log_error "This would push to the WRONG GitHub account!"
    log_error ""
    log_error "Possible causes:"
    log_error "  1. SSH ControlMaster cached a connection from different directory"
    log_error "  2. SSH config Match directive not matching current directory"
    log_error "  3. Remote URL using wrong host alias"
    log_error ""
    log_error "Solutions:"
    log_error "  1. Close cached SSH connections:"
    log_error "     ssh -O exit git@github.com"
    log_error ""
    log_error "  2. Use explicit host alias in remote URL:"
    log_error "     git remote set-url origin git@github.com-${EXPECTED_USER}:<owner>/<repo>.git"
    log_error ""
    log_error "  3. Verify SSH config Match directives:"
    log_error "     grep -A3 'Match host github.com' ~/.ssh/config"
    log_error ""
    exit 2
fi

#=============================================================================
# All Validations Passed
#=============================================================================

exit 0
