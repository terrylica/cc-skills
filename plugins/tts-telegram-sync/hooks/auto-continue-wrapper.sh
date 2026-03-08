#!/usr/bin/env bash
# Auto-Continue Stop Hook — Bash Fast Gate
#
# Fast-path checks (no Bun overhead, <100ms):
# 1. No transcript → allow stop
# 2. sweep_done in state → allow stop
# 3. No .claude/plans/ ref in transcript → allow stop
#
# If all gates pass, pipe stdin to bun auto-continue.ts for MiniMax evaluation.
#
# Secrets: sourced from ~/.claude/.secrets/ccterrybot-telegram
# (MINIMAX_API_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)
set -euo pipefail

ALLOW='{}' # Empty JSON = allow stop

# Read all of stdin into a variable
INPUT=$(cat)

# Fast path 1: No input at all
if [[ -z "$INPUT" ]]; then
    echo "$ALLOW"
    exit 0
fi

# Extract fields via grep (no jq dependency in gate)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

# Fast path 2: No transcript_path
if [[ -z "$TRANSCRIPT_PATH" ]]; then
    echo "$ALLOW"
    exit 0
fi

# Fast path 3: Transcript file doesn't exist
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    echo "$ALLOW"
    exit 0
fi

# Fast paths 4-5 (sweep_done, no plan ref) moved to TypeScript engine
# so they can send Telegram notifications on exit.

# ===== Gate passed — invoke Bun engine =====

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source env vars for MiniMax API
# MINIMAX_API_KEY from secrets file
if [[ -f "$HOME/.claude/.secrets/ccterrybot-telegram" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$HOME/.claude/.secrets/ccterrybot-telegram"
    set +a
fi

# SUMMARY_MODEL and SUMMARY_BASE_URL (match mise.toml values)
export SUMMARY_MODEL="${SUMMARY_MODEL:-MiniMax-M2.5-highspeed}"
export SUMMARY_BASE_URL="${SUMMARY_BASE_URL:-https://api.minimax.io/anthropic}"

# Find bun (same discovery pattern as other hooks)
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
    echo "$ALLOW"
    exit 0
fi

# Pipe original stdin to TypeScript engine
echo "$INPUT" | "$BUN_CMD" "$SCRIPT_DIR/auto-continue.ts"
