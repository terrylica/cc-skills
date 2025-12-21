---
description: Enable autonomous loop mode for long-running tasks
allowed-tools: Read, Write, Bash, AskUserQuestion, Glob
argument-hint: "[-f <file>] [--poc] [--no-focus] [<task description>...]"
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
- `--no-focus`: Skip focus file tracking (100% autonomous, no plan file)
- `<task description>`: Natural language task prompt (remaining text after flags)

## Step 1: Focus File Confirmation

**BEFORE running the bash script**, you MUST confirm the focus file with the user:

1. **Check for explicit file**: If `-f <file>` was provided, use that path.

2. **Check for --no-focus flag**: If `--no-focus` is present, skip to Step 2 with `NO_FOCUS=true`.

3. **Discover focus file** (if no explicit file): Look for files in this priority order:
   - Plan mode system-reminder (if in plan mode, the system-assigned plan file)
   - ITP design specs with `implementation-status: in_progress` in `docs/design/*/spec.md`
   - ITP ADRs with `status: accepted` in `docs/adr/*.md`
   - **Alpha Forge research sessions**: `outputs/research_sessions/*/research_log.md` (up to 3 most recent by mtime)
   - Newest `.md` file in `.claude/plans/` (local or global)

4. **Ask user to confirm** using AskUserQuestion:

   For Alpha Forge projects (detected by `outputs/research_sessions/` existing), include research sessions:

   ```
   AskUserQuestion({
     questions: [{
       question: "Which focus mode for this Ralph session?",
       header: "Focus Mode",
       options: [
         { label: "Continue research sessions", description: "Focus on N most recent research_log.md files" },
         { label: "Specify different file", description: "You'll provide a custom path" },
         { label: "Run without focus", description: "100% autonomous, no plan tracking" }
       ],
       multiSelect: false
     }]
   })
   ```

   For other projects:

   ```
   AskUserQuestion({
     questions: [{
       question: "Which focus mode for this Ralph session?",
       header: "Focus Mode",
       options: [
         { label: "Use discovered file", description: "<path to discovered file>" },
         { label: "Specify different file", description: "You'll provide a custom path" },
         { label: "Run without focus", description: "100% autonomous, no plan tracking" }
       ],
       multiSelect: false
     }]
   })
   ```

5. **Handle response**:
   - If "Continue research sessions" (Alpha Forge): Store all discovered session paths for the hook to read
   - If "Use discovered file": Set `TARGET_FILE` to the discovered path
   - If "Specify different file": Ask user for the path, then set `TARGET_FILE`
   - If "Run without focus": Set `NO_FOCUS=true` (skip focus file tracking entirely)

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
RALPH_CACHE="$HOME/.claude/plugins/cache/cc-skills/ralph"
if [[ -d "$RALPH_CACHE" ]]; then
    # Get highest semantic version from cache directories (exclude 'local')
    RALPH_VERSION=$(ls "$RALPH_CACHE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
else
    RALPH_VERSION="unknown"
fi

echo "========================================"
echo "  RALPH WIGGUM v${RALPH_VERSION:-unknown}"
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

# Create legacy markers for backward compatibility
touch "$PROJECT_DIR/.claude/loop-enabled"
date +%s > "$PROJECT_DIR/.claude/loop-start-timestamp"

# Build unified config JSON with all configurable values
if $POC_MODE; then
    MIN_HOURS=0.083
    MAX_HOURS=0.167
    MIN_ITERS=10
    MAX_ITERS=20
else
    MIN_HOURS=4
    MAX_HOURS=9
    MIN_ITERS=50
    MAX_ITERS=99
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
HOOKS_DIR="$HOME/.claude/plugins/cache/cc-skills/plugins/ralph/hooks"
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
else
    echo "Ralph Loop: PRODUCTION MODE"
    echo "Time limits: 4h minimum / 9h maximum"
    echo "Iterations: 50 minimum / 99 maximum"
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
