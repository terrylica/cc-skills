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
    # SSH validation failed - BLOCK to prevent partial state from chained commands
    # e.g., "git add && git commit && git push" would commit but fail to push

    # Determine if this is a definite failure (should block) or transient (could warn)
    IS_DEFINITE_FAILURE=false
    if echo "$SSH_OUTPUT" | grep -qiE 'connection refused|no route to host|network is unreachable|permission denied|host key verification failed'; then
        IS_DEFINITE_FAILURE=true
    fi

    # Allow override via environment variable (for users who want warn-only behavior)
    STRICT_MODE="${GIT_ACCOUNT_VALIDATOR_STRICT:-true}"

    if [[ "$IS_DEFINITE_FAILURE" == "true" ]] || [[ "$STRICT_MODE" == "true" ]]; then
        log_block "BLOCKED: SSH validation failed"
        log_error "SSH output: $SSH_OUTPUT"
        log_error ""

        # Warn about chained command risk
        if [[ "$IS_CHAINED_COMMAND" == "true" ]]; then
            log_error "⚠️  CHAINED COMMAND DETECTED"
            log_error "Command: $COMMAND"
            log_error ""
            log_error "If allowed, earlier commands (git add, git commit) would succeed"
            log_error "but git push would fail, leaving your repo in a partial state."
            log_error ""
        fi

        log_error "This may indicate:"
        log_error "  • Network issue (Connection refused/timeout)"
        log_error "  • SSH key not loaded"
        log_error "  • GitHub SSH service down"
        log_error ""

        # Suggest which key to load based on expected account
        log_error "Expected account: $EXPECTED_USER"
        log_error ""

        # Find matching identity file from SSH config (if it exists)
        if [[ -f "$HOME/.ssh/config" ]]; then
            # Try to find identity file for expected user
            IDENTITY_FILE=$(grep -A5 "Match host github.com" "$HOME/.ssh/config" 2>/dev/null | \
                            grep -i "IdentityFile.*${EXPECTED_USER}" | \
                            head -1 | \
                            awk '{print $2}' | \
                            sed "s|~|$HOME|g") || true

            if [[ -n "$IDENTITY_FILE" ]]; then
                log_error "Try loading the SSH key:"
                log_error "  ssh-add $IDENTITY_FILE"
            else
                # Fallback: suggest common pattern
                log_error "Try loading the SSH key (common pattern):"
                log_error "  ssh-add ~/.ssh/id_ed25519_${EXPECTED_USER}"
            fi
        else
            log_error "Try loading the SSH key (common pattern):"
            log_error "  ssh-add ~/.ssh/id_ed25519_${EXPECTED_USER}"
        fi
        log_error ""
        log_error "Diagnostic commands:"
        log_error "  1. Test port 22: nc -zv github.com 22"
        log_error "  2. Test port 443: nc -zv github.com 443"
        log_error "  3. Loaded keys: ssh-add -l"
        log_error "  4. Test SSH (port 22): ssh -T git@github.com"
        log_error "  5. Test SSH (port 443): ssh -T -p 443 git@ssh.github.com"
        log_error ""
        log_error "Note: Port 443 fallback was attempted automatically."
        log_error "If port 22 is blocked, ensure your SSH key is loaded for port 443 auth."
        log_error ""

        # Show SSH config location for reference
        if [[ -f "$HOME/.ssh/config" ]]; then
            log_error "SSH config: ~/.ssh/config"
            log_error "View Match directives: grep -A3 'Match host github.com' ~/.ssh/config"
        fi
        log_error ""
        log_error "To disable strict mode: export GIT_ACCOUNT_VALIDATOR_STRICT=false"
        log_error ""
        exit 2  # BLOCK - prevents partial state from chained commands
    else
        # Non-strict mode: warn but allow
        log_info ""
        log_info "⚠️  SSH VALIDATION WARNING - Cannot verify GitHub account"
        log_info ""
        log_info "SSH output: $SSH_OUTPUT"
        log_info "Expected account: $EXPECTED_USER"
        log_info ""
        log_info "Proceeding anyway (strict mode disabled)."
        log_info "If push fails, check: ssh -T git@github.com"
        log_info ""
        exit 0
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
