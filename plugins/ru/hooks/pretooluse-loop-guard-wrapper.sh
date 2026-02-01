#!/usr/bin/env bash
# Ralph Universal - Activation-Gated Global Hooks
#
# FORK of Ralph with Alpha-Forge exclusivity REMOVED.
# Works on ANY project type.
#
# This wrapper implements the "globally registered, activation-gated" pattern:
# - Hook is registered globally in settings.json (PreToolUse:Bash)
# - BUT: Does NOTHING unless Ralph Universal was explicitly started in the project
#
# Activation check happens BEFORE any Bun/TypeScript invocation, avoiding:
# - Unnecessary processing in non-Ralph projects
# - Zero overhead when Ralph Universal is not active
#
# Activation marker: $PROJECT/.claude/ru-state.json with {"state": "running"}
#
# Why Bash wrapper?
# - Pure Bash has no dependencies (no Bun, no Node, no Python)
# - Fast exit for inactive projects (< 1ms)
set -euo pipefail

# ===== ACTIVATION GATE =====
# Check if Ralph Universal is active BEFORE doing anything else.
# This is the key to "globally registered, activation-gated" design.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# Fast path: No project directory = not active
if [[ -z "$PROJECT_DIR" ]]; then
    # Silent exit - output allow response for PreToolUse
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# Check for activation marker: $PROJECT/.claude/ru-state.json
STATE_FILE="$PROJECT_DIR/.claude/ru-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    # No state file = Ralph never started in this project
    # Silent exit - output allow response for PreToolUse
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# Check if state is "running" (not "stopped" or "draining")
# Using grep for speed (no jq dependency in gate)
if ! grep -q '"state"[[:space:]]*:[[:space:]]*"running"' "$STATE_FILE" 2>/dev/null; then
    # State exists but not running = Ralph not active
    # Silent exit - output allow response for PreToolUse
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# ===== RALPH UNIVERSAL IS ACTIVE =====
# Only now do we invoke the TypeScript hook via Bun

# Find bun (same discovery pattern as other Ralph scripts)
BUN_CMD=""
for loc in \
    "$HOME/.local/share/mise/shims/bun" \
    "$HOME/.bun/bin/bun" \
    "/opt/homebrew/bin/bun" \
    "/usr/local/bin/bun" \
    "bun"; do
    if command -v "$loc" &>/dev/null || [[ -x "$loc" ]]; then
        BUN_CMD="$loc"
        break
    fi
done

if [[ -z "$BUN_CMD" ]]; then
    echo "[ru] ERROR: bun not found, cannot run PreToolUse hook" >&2
    # Allow command to proceed even if we can't run the guard
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the TypeScript hook via Bun
# Pass stdin through for hook input
exec "$BUN_CMD" "$SCRIPT_DIR/pretooluse-loop-guard.ts"
