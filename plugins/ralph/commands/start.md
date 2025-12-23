---
description: Enable autonomous loop mode for long-running tasks
allowed-tools: Read, Write, Bash, AskUserQuestion, Glob
argument-hint: "[-f <file>] [--poc | --production] [--no-focus] [<task description>...]"
---

# Ralph Loop: Start

Enable the Ralph Wiggum autonomous improvement loop. Claude will continue working until:

- Task is truly complete (respecting minimum time/iteration thresholds)
- Maximum time limit reached (default: 9 hours)
- Maximum iterations reached (default: 99)
- Kill switch activated (`.claude/STOP_LOOP` file created)

## Arguments

- `-f <file>`: Specify target file for completion tracking (plan, spec, or ADR)
- `--poc`: Use proof-of-concept settings (5 min / 10 min limits, 10/20 iterations)
- `--production`: Use production settings (4h / 9h limits, 50/99 iterations) - skips preset prompt
- `--no-focus`: Skip focus file tracking (100% autonomous, no plan file)
- `<task description>`: Natural language task prompt (remaining text after flags)

## Step 1: Focus File Discovery (Auto-Select)

Discover and auto-select focus files WITHOUT prompting the user (autonomous mode):

1. **Check for explicit file**: If `-f <file>` was provided, use that path. Skip to Step 2.

2. **Check for --no-focus flag**: If `--no-focus` is present, skip to Step 2 with `NO_FOCUS=true`.

3. **Auto-discover focus file** (if no explicit file):

   **For Alpha Forge projects** (detected by `outputs/research_sessions/` existing):
   - Auto-select up to 3 most recent `outputs/research_sessions/*/research_log.md` files
   - NO user prompt - proceed directly to Step 2
   - Store paths in config for the hook to read

   **For other projects**, discover in priority order:
   - Plan mode system-reminder (if in plan mode, the system-assigned plan file)
   - ITP design specs with `implementation-status: in_progress` in `docs/design/*/spec.md`
   - ITP ADRs with `status: accepted` in `docs/adr/*.md`
   - Newest `.md` file in `.claude/plans/` (local or global)

4. **Only prompt if truly ambiguous** (multiple ITP specs or ADRs with same priority):
   - Use AskUserQuestion to let user choose
   - Otherwise, auto-select the most recent file and proceed

5. **If nothing discovered**: Proceed with `NO_FOCUS=true` (exploration mode)

## Step 1.5: Preset Selection (Conditional)

**Only prompt if no preset flag (`--poc` or `--production`) was provided.**

If the arguments do NOT contain `--poc` AND do NOT contain `--production`:

Use AskUserQuestion with questions:

- question: "Select loop configuration preset:"
  header: "Preset"
  options:
  - label: "Production Mode (Recommended)"
    description: "4h-9h, 50-99 iterations - standard autonomous work"
  - label: "POC Mode (Fast)"
    description: "5min-10min, 10-20 iterations - ideal for testing"
  - label: "Custom"
    description: "Specify your own time/iteration limits"
    multiSelect: false

Based on selection:

- **"Production Mode"** → Proceed to Step 2 with production defaults
- **"POC Mode"** → Proceed to Step 2 with POC settings
- **"Custom"** → Ask follow-up questions for time/iteration limits:

  Use AskUserQuestion with questions:
  - question: "Select time limits:"
    header: "Time"
    options:
    - label: "1h - 2h"
      description: "Short session"
    - label: "2h - 4h"
      description: "Medium session"
    - label: "4h - 9h (Production)"
      description: "Standard session"
      multiSelect: false

  - question: "Select iteration limits:"
    header: "Iterations"
    options:
    - label: "10 - 20"
      description: "Quick test"
    - label: "25 - 50"
      description: "Medium session"
    - label: "50 - 99 (Production)"
      description: "Standard session"
      multiSelect: false

**If `--poc` or `--production` flag was provided**: Skip this step entirely (backward compatible).

## Step 2: Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_START_SCRIPT'
# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SETTINGS="$HOME/.claude/settings.json"
MARKER="ralph/hooks/"

# ===== VERSION BANNER =====
# Retrieve version from cache directory (source of truth: installed plugin version)
# FAIL FAST: Exit if version cannot be determined (no fallbacks)
RALPH_CACHE="$HOME/.claude/plugins/cache/cc-skills/ralph"
RALPH_VERSION=""
RALPH_SOURCE="cache"

if [[ -d "$RALPH_CACHE" ]]; then
    # Check for 'local' directory first (development symlink takes priority)
    if [[ -d "$RALPH_CACHE/local" ]]; then
        RALPH_SOURCE="local"
        # Follow symlink to find source repo and read version from package.json
        LOCAL_PATH=$(readlink -f "$RALPH_CACHE/local" 2>/dev/null || readlink "$RALPH_CACHE/local" 2>/dev/null)
        if [[ -n "$LOCAL_PATH" ]]; then
            # Navigate up from plugins/ralph to repo root to find package.json
            REPO_ROOT=$(cd "$LOCAL_PATH" && cd ../.. && pwd 2>/dev/null)
            if [[ -f "$REPO_ROOT/package.json" ]]; then
                RALPH_VERSION=$(jq -r '.version // empty' "$REPO_ROOT/package.json" 2>/dev/null)
            fi
        fi
    else
        # Get highest semantic version from cache directories
        RALPH_VERSION=$(ls "$RALPH_CACHE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    fi
fi

# FAIL FAST: Version must be determined
if [[ -z "$RALPH_VERSION" ]]; then
    echo "ERROR: Cannot determine Ralph version!"
    echo ""
    echo "Possible causes:"
    echo "  1. Plugin not installed: Run /plugin install cc-skills"
    echo "  2. Local symlink broken: Check ~/.claude/plugins/cache/cc-skills/ralph/local"
    echo "  3. Missing package.json in source repo"
    echo ""
    echo "Cache directory: $RALPH_CACHE"
    echo "Source: $RALPH_SOURCE"
    exit 1
fi

echo "========================================"
echo "  RALPH WIGGUM v${RALPH_VERSION} (${RALPH_SOURCE})"
echo "  Autonomous Loop Mode"
echo "========================================"
echo ""

# Check if hooks are installed
HOOKS_INSTALLED=false
if command -v jq &>/dev/null && [[ -f "$SETTINGS" ]]; then
    HOOK_COUNT=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0")
    if [[ "$HOOK_COUNT" -gt 0 ]]; then
        HOOKS_INSTALLED=true
    fi
fi

# Warn if hooks not installed
if [[ "$HOOKS_INSTALLED" == "false" ]]; then
    echo "WARNING: Hooks not installed!"
    echo ""
    echo "The loop will NOT work without hooks registered."
    echo ""
    echo "To fix:"
    echo "  1. Run: /ralph:hooks install"
    echo "  2. Restart Claude Code"
    echo "  3. Run: /ralph:start again"
    echo ""
    exit 1
fi

# ===== ARGUMENT PARSING =====
# Syntax: /ralph:start [-f <file>] [--poc] [--no-focus] [<task description>...]

ARGS="${ARGUMENTS:-}"
TARGET_FILE=""
POC_MODE=false
NO_FOCUS=false
TASK_PROMPT=""

# Extract -f flag with regex (handles paths without spaces)
if [[ "$ARGS" =~ -f[[:space:]]+([^[:space:]]+) ]]; then
    TARGET_FILE="${BASH_REMATCH[1]}"
    # Remove -f and path from ARGS for remaining processing
    ARGS="${ARGS//-f ${TARGET_FILE}/}"
fi

# Detect --poc flag
if [[ "$ARGS" == *"--poc"* ]]; then
    POC_MODE=true
    ARGS="${ARGS//--poc/}"
fi

# Detect --production flag (skips preset prompt, uses production defaults)
PRODUCTION_MODE=false
if [[ "$ARGS" == *"--production"* ]]; then
    PRODUCTION_MODE=true
    ARGS="${ARGS//--production/}"
fi

# Detect --no-focus flag
if [[ "$ARGS" == *"--no-focus"* ]]; then
    NO_FOCUS=true
    ARGS="${ARGS//--no-focus/}"
fi

# Remaining text after flags = task_prompt (trim whitespace)
TASK_PROMPT=$(echo "$ARGS" | xargs 2>/dev/null || echo "$ARGS")

# Resolve relative path to absolute
if [[ -n "$TARGET_FILE" && "$TARGET_FILE" != /* ]]; then
    TARGET_FILE="$PROJECT_DIR/$TARGET_FILE"
fi

# Validate file exists (warn but continue)
if [[ -n "$TARGET_FILE" && ! -e "$TARGET_FILE" ]]; then
    echo "WARNING: Target file does not exist: $TARGET_FILE"
    echo "         Loop will proceed but file discovery may be used instead."
    echo ""
fi

# ===== STATE MACHINE TRANSITION =====
# State machine: STOPPED → RUNNING → DRAINING → STOPPED
mkdir -p "$PROJECT_DIR/.claude"

# Check current state (if any)
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"
CURRENT_STATE="stopped"
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE=$(jq -r '.state // "stopped"' "$STATE_FILE" 2>/dev/null || echo "stopped")
fi

# Validate state transition: STOPPED → RUNNING
if [[ "$CURRENT_STATE" != "stopped" ]]; then
    echo "ERROR: Loop already in state '$CURRENT_STATE'"
    echo "       Run /ralph:stop first to reset state"
    exit 1
fi

# Transition to RUNNING state
echo '{"state": "running"}' > "$STATE_FILE"

# ERROR TRAP: Reset state if script fails from this point forward
# This prevents orphaned "running" state when setup fails (e.g., adapter detection, config parsing)
cleanup_on_error() {
    echo ""
    echo "ERROR: Script failed after state transition. Resetting state to 'stopped'."
    echo '{"state": "stopped"}' > "$STATE_FILE"
    rm -f "$PROJECT_DIR/.claude/loop-enabled"
    rm -f "$PROJECT_DIR/.claude/loop-start-timestamp"
    rm -f "$PROJECT_DIR/.claude/ralph-config.json"
    rm -f "$PROJECT_DIR/.claude/loop-config.json"
    exit 1
}
trap cleanup_on_error ERR

# Create legacy markers for backward compatibility
touch "$PROJECT_DIR/.claude/loop-enabled"
date +%s > "$PROJECT_DIR/.claude/loop-start-timestamp"

# Clear previous stop reason cache (new session = fresh slate)
rm -f "$HOME/.claude/ralph-stop-reason.json"

# Build unified config JSON with all configurable values
# Note: --poc and --production flags skip preset prompts (backward compatibility)
if $POC_MODE; then
    MIN_HOURS=0.083
    MAX_HOURS=0.167
    MIN_ITERS=10
    MAX_ITERS=20
elif $PRODUCTION_MODE; then
    MIN_HOURS=4
    MAX_HOURS=9
    MIN_ITERS=50
    MAX_ITERS=99
else
    # Default: Production settings (will be overridden by AskUserQuestion if no preset flag)
    MIN_HOURS=${SELECTED_MIN_HOURS:-4}
    MAX_HOURS=${SELECTED_MAX_HOURS:-9}
    MIN_ITERS=${SELECTED_MIN_ITERS:-50}
    MAX_ITERS=${SELECTED_MAX_ITERS:-99}
fi

# Generate unified ralph-config.json (v2.0 schema)
CONFIG_JSON=$(jq -n \
    --arg state "running" \
    --argjson poc_mode "$POC_MODE" \
    --argjson no_focus "$NO_FOCUS" \
    --arg target_file "$TARGET_FILE" \
    --arg task_prompt "$TASK_PROMPT" \
    --argjson min_hours "$MIN_HOURS" \
    --argjson max_hours "$MAX_HOURS" \
    --argjson min_iterations "$MIN_ITERS" \
    --argjson max_iterations "$MAX_ITERS" \
    '{
        version: "2.0.0",
        state: $state,
        poc_mode: $poc_mode,
        no_focus: $no_focus,
        loop_limits: {
            min_hours: $min_hours,
            max_hours: $max_hours,
            min_iterations: $min_iterations,
            max_iterations: $max_iterations
        }
    }
    + (if $target_file != "" then {target_file: $target_file} else {} end)
    + (if $task_prompt != "" then {task_prompt: $task_prompt} else {} end)'
)

echo "$CONFIG_JSON" > "$PROJECT_DIR/.claude/ralph-config.json"

# Legacy config for backward compatibility
LEGACY_CONFIG=$(jq -n \
    --argjson min_hours "$MIN_HOURS" \
    --argjson max_hours "$MAX_HOURS" \
    --argjson min_iterations "$MIN_ITERS" \
    --argjson max_iterations "$MAX_ITERS" \
    --argjson no_focus "$NO_FOCUS" \
    --arg target_file "$TARGET_FILE" \
    --arg task_prompt "$TASK_PROMPT" \
    '{
        min_hours: $min_hours,
        max_hours: $max_hours,
        min_iterations: $min_iterations,
        max_iterations: $max_iterations,
        no_focus: $no_focus
    }
    + (if $target_file != "" then {target_file: $target_file} else {} end)
    + (if $task_prompt != "" then {task_prompt: $task_prompt} else {} end)'
)
echo "$LEGACY_CONFIG" > "$PROJECT_DIR/.claude/loop-config.json"

# ===== ADAPTER DETECTION =====
# Detect project-specific adapter using Python
# Use same path logic as version detection above
if [[ -d "$RALPH_CACHE/local" ]]; then
    HOOKS_DIR="$RALPH_CACHE/local/hooks"
else
    HOOKS_DIR="$RALPH_CACHE/$RALPH_VERSION/hooks"
fi
ADAPTER_NAME="universal"
if [[ -d "$HOOKS_DIR" ]]; then
    ADAPTER_NAME=$(cd "$HOOKS_DIR" && python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '.')
try:
    from core.registry import AdapterRegistry
    AdapterRegistry.discover(Path('adapters'))
    adapter = AdapterRegistry.get_adapter(Path('$PROJECT_DIR'))
    print(adapter.name)
except Exception:
    print('universal')
" 2>/dev/null || echo "universal")
fi

# ===== STATUS OUTPUT =====
if $POC_MODE; then
    echo "Ralph Loop: POC MODE"
    echo "Time limits: 5 min minimum / 10 min maximum"
    echo "Iterations: 10 minimum / 20 maximum"
elif $PRODUCTION_MODE; then
    echo "Ralph Loop: PRODUCTION MODE (via --production flag)"
    echo "Time limits: 4h minimum / 9h maximum"
    echo "Iterations: 50 minimum / 99 maximum"
else
    echo "Ralph Loop: PRODUCTION MODE"
    echo "Time limits: ${MIN_HOURS}h minimum / ${MAX_HOURS}h maximum"
    echo "Iterations: ${MIN_ITERS} minimum / ${MAX_ITERS} maximum"
fi

echo ""
echo "Adapter: $ADAPTER_NAME"
if [[ "$ADAPTER_NAME" == "alpha-forge" ]]; then
    echo "  → Expert-synthesis convergence (WFE, diminishing returns, patience)"
    echo "  → Reads metrics from outputs/runs/*/summary.json"
elif [[ "$ADAPTER_NAME" == "universal" ]]; then
    echo "  → Standard RSSI completion detection"
fi

if $NO_FOCUS; then
    echo ""
    echo "Focus mode: DISABLED (100% autonomous, no plan tracking)"
elif [[ -n "$TARGET_FILE" ]]; then
    echo ""
    echo "Target file: $TARGET_FILE"
fi

if [[ -n "$TASK_PROMPT" ]]; then
    echo ""
    echo "Task: $TASK_PROMPT"
fi

echo ""
echo "State: RUNNING (was: $CURRENT_STATE)"
echo "Config: $PROJECT_DIR/.claude/ralph-config.json"
echo ""
echo "To stop: /ralph:stop"
echo "Kill switch: touch $PROJECT_DIR/.claude/STOP_LOOP"
echo ""
echo "Note: If you just installed hooks, restart Claude Code for them to take effect."
RALPH_START_SCRIPT
```

Run the bash script above to enable loop mode.

## Step 3: Alpha Forge - OODA Initialization

**If this is an Alpha Forge project** (detected by `outputs/research_sessions/` existing):

After enabling loop mode, begin the OODA cycle immediately:

### OBSERVE

1. Read `outputs/research_sessions/*/research_summary.md` (most recent)
2. Read `outputs/research_sessions/*/research_log.md` for expert recommendations
3. Check `ROADMAP.md` for current P0/P1 priorities

### ORIENT

1. Compare metrics to previous session (look for delta)
2. Synthesize expert recommendations from research_log.md
3. Self-critique: Does the planned approach align with ROADMAP?

### DECIDE

Use the checkpoint gate:

- Sharpe improved > 10%? → CONTINUE
- Sharpe improved < 5% for 2 sessions? → PIVOT to next ROADMAP item
- WFE < 0.5? → STOP and address overfitting first

### ACT

Invoke `/research` with the appropriate strategy:

```
/research <path/to/strategy.yaml> --iterations=5 --objective=sharpe
```

Ralph RSSI is **supplementary** to alpha-forge's `/research`:

- `/research` owns the inner loop (5 iterations, 5 expert subagents)
- Ralph owns the outer loop (session-to-session learning, OODA decisions)

**Do NOT ask the user what to work on.** Proceed autonomously through OODA.
