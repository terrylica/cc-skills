---
description: Enable autonomous loop mode for ANY project (no Alpha-Forge restriction)
allowed-tools: Bash, AskUserQuestion
argument-hint: "[--poc | --production]"
---

# Ralph Universal: Start

Enable autonomous loop mode for **any project type**. This is a fork of Ralph with the Alpha-Forge exclusivity removed.

## Arguments

- `--poc`: Use proof-of-concept settings (5 min / 10 min limits, 10/20 iterations)
- `--production`: Use production settings (4h / 9h limits, 50/99 iterations)

## Step 1: Preset Selection

Use AskUserQuestion with questions:

- question: "Select loop configuration preset:"
  header: "Preset"
  multiSelect: false
  options:
  - label: "POC Mode (Recommended)"
    description: "5min-10min, 10-20 iterations - ideal for testing"
  - label: "Production Mode"
    description: "4h-9h, 50-99 iterations - standard autonomous work"

## Step 2: Execution

```bash
/usr/bin/env bash << 'RALPH_UNIVERSAL_START'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "========================================"
echo "  RALPH UNIVERSAL"
echo "  Autonomous Loop Mode (Any Project)"
echo "========================================"
echo ""

# Parse arguments
ARGS="${ARGUMENTS:-}"
POC_MODE=false
PRODUCTION_MODE=false

if [[ "$ARGS" == *"--poc"* ]]; then
    POC_MODE=true
fi
if [[ "$ARGS" == *"--production"* ]]; then
    PRODUCTION_MODE=true
fi

# Set limits based on mode
if $POC_MODE; then
    MIN_HOURS=0.083
    MAX_HOURS=0.167
    MIN_ITERS=10
    MAX_ITERS=20
    MODE_NAME="POC"
else
    MIN_HOURS=4
    MAX_HOURS=9
    MIN_ITERS=50
    MAX_ITERS=99
    MODE_NAME="PRODUCTION"
fi

# Check for uv
UV_CMD=""
for loc in "$HOME/.local/share/mise/shims/uv" "$HOME/.local/bin/uv" "/opt/homebrew/bin/uv" "uv"; do
    if command -v "$loc" &>/dev/null || [[ -x "$loc" ]]; then
        UV_CMD="$loc"
        break
    fi
done

if [[ -z "$UV_CMD" ]]; then
    echo "ERROR: uv is required. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Create state directory
mkdir -p "$PROJECT_DIR/.claude"

# Check current state
STATE_FILE="$PROJECT_DIR/.claude/ru-state.json"
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE=$(jq -r '.state // "stopped"' "$STATE_FILE" 2>/dev/null || echo "stopped")
    if [[ "$CURRENT_STATE" != "stopped" ]]; then
        echo "ERROR: Loop already in state '$CURRENT_STATE'"
        echo "       Run /ru:stop first"
        exit 1
    fi
fi

# Transition to RUNNING state
echo '{"state": "running"}' > "$STATE_FILE"
date +%s > "$PROJECT_DIR/.claude/ru-start-timestamp"

# Create config
CONFIG_FILE="$PROJECT_DIR/.claude/ru-config.json"
jq -n \
    --arg state "running" \
    --argjson min_hours "$MIN_HOURS" \
    --argjson max_hours "$MAX_HOURS" \
    --argjson min_iterations "$MIN_ITERS" \
    --argjson max_iterations "$MAX_ITERS" \
    '{
        version: "1.0.0",
        state: $state,
        loop_limits: {
            min_hours: $min_hours,
            max_hours: $max_hours,
            min_iterations: $min_iterations,
            max_iterations: $max_iterations
        }
    }' > "$CONFIG_FILE"

echo "Mode: $MODE_NAME"
echo "Time limits: ${MIN_HOURS}h minimum / ${MAX_HOURS}h maximum"
echo "Iterations: ${MIN_ITERS} minimum / ${MAX_ITERS} maximum"
echo ""
echo "Project: $PROJECT_DIR"
echo "State: RUNNING"
echo ""
echo "To stop: /ru:stop"
echo "Kill switch: touch $PROJECT_DIR/.claude/STOP_LOOP"
RALPH_UNIVERSAL_START
```

Run the bash script above to enable loop mode.

## After Starting

The loop will continue until:

- Maximum time/iterations reached
- You run `/ru:stop`
- Kill switch file created (`.claude/STOP_LOOP`)

Unlike regular Ralph, this works on **any project** - not just Alpha-Forge ML workflows.
