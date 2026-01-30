#!/usr/bin/env bash
# Ralph Universal - Activation-Gated Global Hooks
#
# FORK of Ralph with Alpha-Forge exclusivity REMOVED.
# Works on ANY project type.
#
# This wrapper implements the "globally registered, activation-gated" pattern:
# - Hook is registered globally in settings.json
# - BUT: Does NOTHING unless Ralph Universal was explicitly started in the project
#
# Activation check happens BEFORE any Python/uv invocation, avoiding:
# - Broken .venv issues (uv inspects local venv before running scripts)
# - Unnecessary processing in non-Ralph projects
# - Zero overhead when Ralph Universal is not active
#
# Activation marker: $PROJECT/.claude/ralph-universal-state.json with {"state": "running"}
#
# Why Bash wrapper?
# - Pure Bash has no dependencies (no uv, no Python, no venv)
# - Fast exit for inactive projects (< 1ms)
# - Avoids uv's project discovery walk-up that inspects broken .venv
set -euo pipefail

# ===== ACTIVATION GATE =====
# Check if Ralph is active BEFORE doing anything else.
# This is the key to "globally registered, activation-gated" design.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# Fast path: No project directory = not active
if [[ -z "$PROJECT_DIR" ]]; then
    # Silent exit - output empty JSON to allow stop
    echo '{}'
    exit 0
fi

# Check for activation marker: $PROJECT/.claude/ralph-universal-state.json
STATE_FILE="$PROJECT_DIR/.claude/ralph-universal-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
    # No state file = Ralph never started in this project
    # Silent exit - output empty JSON to allow stop
    echo '{}'
    exit 0
fi

# Check if state is "running" (not "stopped" or "draining")
# Using grep for speed (no jq dependency in gate)
if ! grep -q '"state"[[:space:]]*:[[:space:]]*"running"' "$STATE_FILE" 2>/dev/null; then
    # State exists but not running = Ralph not active
    # Silent exit - output empty JSON to allow stop
    echo '{}'
    exit 0
fi

# ===== RALPH IS ACTIVE =====
# Only now do we invoke the Python script via uv
# Use --no-project to prevent uv from inspecting local .venv

# Find uv (same discovery pattern as other Ralph scripts)
UV_CMD=""
for loc in \
    "$HOME/.local/share/mise/shims/uv" \
    "$HOME/.local/bin/uv" \
    "$HOME/.cargo/bin/uv" \
    "/opt/homebrew/bin/uv" \
    "/usr/local/bin/uv" \
    "uv"; do
    if command -v "$loc" &>/dev/null || [[ -x "$loc" ]]; then
        UV_CMD="$loc"
        break
    fi
done

if [[ -z "$UV_CMD" ]]; then
    echo "[ralph-universal] ERROR: uv not found, cannot run Stop hook" >&2
    echo '{}'
    exit 0
fi

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Python script with --no-project to avoid local .venv inspection
# Pass stdin through for hook input
exec "$UV_CMD" run --no-project "$SCRIPT_DIR/loop-until-done.py"
