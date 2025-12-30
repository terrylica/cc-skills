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
- `--skip-constraint-scan`: Skip constraint scanner (power users, v3.0.0+)
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

   **For other projects** (⚠️ hooks will skip — see [Alpha-Forge Exclusivity](../README.md#alpha-forge-exclusivity-v802)), discover in priority order:
   - Plan mode system-reminder (if in plan mode, the system-assigned plan file)
   - ITP design specs with `implementation-status: in_progress` in `docs/design/*/spec.md`
   - ITP ADRs with `status: accepted` in `docs/adr/*.md`
   - Newest `.md` file in `.claude/plans/` (local or global)

4. **Only prompt if truly ambiguous** (multiple ITP specs or ADRs with same priority):
   - Use AskUserQuestion to let user choose
   - Otherwise, auto-select the most recent file and proceed

5. **If nothing discovered**: Proceed with `NO_FOCUS=true` (exploration mode)

## Step 1.4: Constraint Scanning (Alpha Forge Only)

**Purpose**: Detect environment constraints before loop starts. Results inform RSSI behavior.

**Skip if**: `--skip-constraint-scan` flag provided (power users).

Run the constraint scanner:

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'CONSTRAINT_SCAN_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ARGS="${ARGUMENTS:-}"

# Check for skip flag
if [[ "$ARGS" == *"--skip-constraint-scan"* ]]; then
    echo "Constraint scan: SKIPPED (--skip-constraint-scan flag)"
    exit 0
fi

# Find scanner script in plugin cache
RALPH_CACHE="$HOME/.claude/plugins/cache/cc-skills/ralph"
SCANNER_SCRIPT=""

if [[ -d "$RALPH_CACHE/local" ]]; then
    SCANNER_SCRIPT="$RALPH_CACHE/local/scripts/constraint-scanner.py"
elif [[ -d "$RALPH_CACHE" ]]; then
    # Get highest version
    RALPH_VERSION=$(ls "$RALPH_CACHE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    if [[ -n "$RALPH_VERSION" ]]; then
        SCANNER_SCRIPT="$RALPH_CACHE/$RALPH_VERSION/scripts/constraint-scanner.py"
    fi
fi

# Skip if scanner not found (older version without scanner)
if [[ -z "$SCANNER_SCRIPT" ]] || [[ ! -f "$SCANNER_SCRIPT" ]]; then
    echo "Constraint scan: SKIPPED (scanner not found, upgrade to v9.2.0+)"
    exit 0
fi

# Run scanner
echo "Running constraint scanner..."
SCAN_OUTPUT=$(uv run "$SCANNER_SCRIPT" --project "$PROJECT_DIR" 2>&1)
SCAN_EXIT=$?

if [[ $SCAN_EXIT -eq 2 ]]; then
    echo ""
    echo "========================================"
    echo "  CRITICAL CONSTRAINTS DETECTED"
    echo "========================================"
    echo ""
    echo "$SCAN_OUTPUT" | jq -r '.constraints[] | select(.severity == "critical") | "  ⛔ \(.description)"' 2>/dev/null || echo "$SCAN_OUTPUT"
    echo ""
    echo "Action: Address critical constraints before starting loop."
    echo "        Use --skip-constraint-scan to bypass (not recommended)."
    exit 2
elif [[ $SCAN_EXIT -eq 0 ]]; then
    # Parse and display summary
    CRITICAL_COUNT=$(echo "$SCAN_OUTPUT" | jq '[.constraints[] | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
    HIGH_COUNT=$(echo "$SCAN_OUTPUT" | jq '[.constraints[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
    TOTAL_COUNT=$(echo "$SCAN_OUTPUT" | jq '.constraints | length' 2>/dev/null || echo "0")

    echo "Constraint scan complete:"
    echo "  Critical: $CRITICAL_COUNT | High: $HIGH_COUNT | Total: $TOTAL_COUNT"

    # Save results for AUQ to read
    mkdir -p "$PROJECT_DIR/.claude"
    echo "$SCAN_OUTPUT" > "$PROJECT_DIR/.claude/ralph-constraint-scan.json"
else
    echo "Constraint scan: WARNING (scanner returned exit code $SCAN_EXIT)"
    echo "$SCAN_OUTPUT" | head -5
fi
CONSTRAINT_SCAN_SCRIPT
```

If the scanner exits with code 2 (critical constraints), stop and inform user.

## Step 1.5: Preset Confirmation (ALWAYS)

**ALWAYS prompt for preset confirmation.** Flags pre-select the option but user confirms before execution.

**If `--poc` flag was provided:**

Use AskUserQuestion with questions:

- question: "Confirm loop configuration:"
  header: "Preset"
  multiSelect: false
  options:
  - label: "POC Mode (Recommended)"
    description: "5min-10min, 10-20 iterations - selected via --poc flag"
  - label: "Production Mode"
    description: "4h-9h, 50-99 iterations"
  - label: "Custom"
    description: "Specify your own time/iteration limits"

**If `--production` flag was provided:**

Use AskUserQuestion with questions:

- question: "Confirm loop configuration:"
  header: "Preset"
  multiSelect: false
  options:
  - label: "Production Mode (Recommended)"
    description: "4h-9h, 50-99 iterations - selected via --production flag"
  - label: "POC Mode"
    description: "5min-10min, 10-20 iterations"
  - label: "Custom"
    description: "Specify your own time/iteration limits"

**If no preset flag was provided:**

Use AskUserQuestion with questions:

- question: "Select loop configuration preset:"
  header: "Preset"
  multiSelect: false
  options:
  - label: "Production Mode (Recommended)"
    description: "4h-9h, 50-99 iterations - standard autonomous work"
  - label: "POC Mode (Fast)"
    description: "5min-10min, 10-20 iterations - ideal for testing"
  - label: "Custom"
    description: "Specify your own time/iteration limits"

Based on selection:

- **"Production Mode"** → Proceed to Step 1.6 (if Alpha Forge) or Step 2 with production defaults
- **"POC Mode"** → Proceed to Step 1.6 (if Alpha Forge) or Step 2 with POC settings
- **"Custom"** → Ask follow-up questions for time/iteration limits:

  Use AskUserQuestion with questions:
  - question: "Select time limits:"
    header: "Time"
    multiSelect: false
    options:
    - label: "1h - 2h"
      description: "Short session"
    - label: "2h - 4h"
      description: "Medium session"
    - label: "4h - 9h (Production)"
      description: "Standard session"

  - question: "Select iteration limits:"
    header: "Iterations"
    multiSelect: false
    options:
    - label: "10 - 20"
      description: "Quick test"
    - label: "25 - 50"
      description: "Medium session"
    - label: "50 - 99 (Production)"
      description: "Standard session"

## Step 1.6: Session Guidance (Alpha Forge Only)

**Only for Alpha Forge projects** (detected by adapter). Other projects skip to Step 2.

### 1.6.1: Check for Previous Guidance

After Step 1.5 completes, check if guidance exists in the config file:

```bash
GUIDANCE_EXISTS="false"
if [[ -f "$PROJECT_DIR/.claude/ralph-config.json" ]]; then
    GUIDANCE_EXISTS=$(jq -r 'if .guidance then "true" else "false" end' "$PROJECT_DIR/.claude/ralph-config.json" 2>/dev/null || echo "false")
fi
```

### 1.6.2: Binary Keep/Reconfigure (If Previous Exists)

If `GUIDANCE_EXISTS == "true"`:

Use AskUserQuestion:

- question: "Previous session had custom guidance. Keep it or reconfigure?"
  header: "Guidance"
  options:
  - label: "Keep existing guidance (Recommended)"
    description: "Use stored forbidden/encouraged lists from last session"
  - label: "Reconfigure guidance"
    description: "Set new forbidden/encouraged lists"
    multiSelect: false

- If "Keep existing" → Skip to Step 2 (guidance already in config)
- If "Reconfigure" → Continue to 1.6.2.5

### 1.6.2.5: Load Constraint Scan Results

**Purpose**: Wire scanner HIGH severity constraints to pre-select forbidden items.

Read the constraint scan JSON from Step 1.4 (if it exists):

```bash
/usr/bin/env bash << 'LOAD_SCAN_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCAN_FILE="$PROJECT_DIR/.claude/ralph-constraint-scan.json"

if [[ -f "$SCAN_FILE" ]]; then
    # Extract HIGH severity constraints for forbidden pre-selection
    HIGH_CONSTRAINTS=$(jq -r '[.constraints[] | select(.severity == "high") | .description] | join("\n")' "$SCAN_FILE" 2>/dev/null)
    HIGH_COUNT=$(jq '[.constraints[] | select(.severity == "high")] | length' "$SCAN_FILE" 2>/dev/null || echo "0")

    # Extract builtin_busywork categories for encouraged options
    BUSYWORK_CATEGORIES=$(jq -r '[.builtin_busywork[] | .name] | join("\n")' "$SCAN_FILE" 2>/dev/null)
    BUSYWORK_COUNT=$(jq '.builtin_busywork | length' "$SCAN_FILE" 2>/dev/null || echo "0")

    echo "Constraint scan results loaded:"
    echo "  HIGH severity constraints: $HIGH_COUNT"
    echo "  Busywork categories: $BUSYWORK_COUNT"

    if [[ "$HIGH_COUNT" -gt 0 ]]; then
        echo ""
        echo "HIGH severity items (will pre-select as forbidden):"
        echo "$HIGH_CONSTRAINTS" | head -5
    fi
else
    echo "No constraint scan found (Step 1.4 was skipped or failed)"
fi
LOAD_SCAN_SCRIPT
```

**Claude Instruction**: When presenting AUQ in Steps 1.6.3-1.6.5:

1. If HIGH severity constraints exist, **mention them as recommended forbidden items**
2. If busywork categories exist, **use them to inform encouraged options**
3. Include constraint scan context in the AUQ question descriptions

### 1.6.3: Forbidden Items (multiSelect, closed list)

**Note**: If Step 1.6.2.5 found HIGH severity constraints, pre-populate the question with them.

Use AskUserQuestion:

- question: "What should RSSI avoid? (HIGH severity from constraint scan pre-selected)"
  header: "Forbidden"
  multiSelect: true
  options:
  - label: "Documentation updates"
    description: "README, CHANGELOG, docstrings, comments"
  - label: "Dependency upgrades"
    description: "Version bumps, renovate PRs, package updates"
  - label: "Test coverage expansion"
    description: "Adding tests for untested code"
  - label: "Linting/formatting"
    description: "Style issues, import sorting, code formatting"
  - label: "CI/CD modifications"
    description: "Workflow files, GitHub Actions, pipelines"
  - label: "Type hint additions"
    description: "Adding type annotations to untyped code"
  - label: "TODO/FIXME cleanup"
    description: "Addressing inline code comments"
  - label: "Security patches"
    description: "Dependency CVE fixes, secret rotation"
  - label: "Git history cleanup"
    description: "Squashing, rebasing, commit message edits"
  - label: "Refactoring"
    description: "Code restructuring without behavior change"

### 1.6.4: Custom Forbidden (Follow-up)

After multiSelect, ask for custom additions:

Use AskUserQuestion:

- question: "Add custom forbidden items? (comma-separated)"
  header: "Custom"
  multiSelect: false
  options:
  - label: "Enter custom items"
    description: "Type additional forbidden phrases, e.g., 'database migrations, API changes'"
  - label: "Skip custom items"
    description: "Use only selected categories above"

If "Enter custom items" selected → Parse user's "Other" input, split by comma, trim whitespace.

### 1.6.5: Encouraged Items (multiSelect, closed list)

Use AskUserQuestion:

- question: "What should RSSI prioritize? (Select all that apply)"
  header: "Encouraged"
  multiSelect: true
  options:
  - label: "ROADMAP P0 items"
    description: "Highest priority tasks from project roadmap"
  - label: "Performance improvements"
    description: "Speed, memory, efficiency optimizations"
  - label: "Bug fixes"
    description: "Fix known issues and regressions"
  - label: "Research experiments"
    description: "Try new approaches (Alpha Forge /research)"

### 1.6.6: Custom Encouraged (Follow-up)

Same pattern as 1.6.4:

Use AskUserQuestion:

- question: "Add custom encouraged items? (comma-separated)"
  header: "Custom"
  multiSelect: false
  options:
  - label: "Enter custom items"
    description: "Type additional encouraged phrases, e.g., 'Sharpe ratio, feature engineering'"
  - label: "Skip custom items"
    description: "Use only selected categories above"

### 1.6.7: Update Config (EXECUTE)

**IMPORTANT**: After collecting responses from Steps 1.6.3-1.6.6, you MUST write them to config.

1. **Collect responses** from the AUQ steps above:
   - `FORBIDDEN_ITEMS`: Selected labels from 1.6.3 + custom items from 1.6.4 (if any)
   - `ENCOURAGED_ITEMS`: Selected labels from 1.6.5 + custom items from 1.6.6 (if any)

2. **Write to config** using the Bash tool with this script (substitute actual values):

```bash
/usr/bin/env bash << 'GUIDANCE_WRITE_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"

# Substitute these with actual AUQ responses:
FORBIDDEN_JSON='["Documentation updates", "Dependency upgrades"]'  # From 1.6.3 + 1.6.4
ENCOURAGED_JSON='["ROADMAP P0 items", "Research experiments"]'     # From 1.6.5 + 1.6.6

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Merge guidance into existing config (or create new)
mkdir -p "$PROJECT_DIR/.claude"
if [[ -f "$CONFIG_FILE" ]]; then
    jq --argjson forbidden "$FORBIDDEN_JSON" \
       --argjson encouraged "$ENCOURAGED_JSON" \
       --arg timestamp "$TIMESTAMP" \
       '.guidance = {forbidden: $forbidden, encouraged: $encouraged, timestamp: $timestamp}' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
    jq -n --argjson forbidden "$FORBIDDEN_JSON" \
          --argjson encouraged "$ENCOURAGED_JSON" \
          --arg timestamp "$TIMESTAMP" \
          '{version: "3.0.0", guidance: {forbidden: $forbidden, encouraged: $encouraged, timestamp: $timestamp}}' \
          > "$CONFIG_FILE"
fi

echo "Guidance saved to $CONFIG_FILE"
jq '.guidance' "$CONFIG_FILE"
GUIDANCE_WRITE_SCRIPT
```

**Execution model**: Claude interprets Steps 1.6.3-1.6.6 (uses AskUserQuestion tool), collects responses, then runs the bash script above with actual values substituted.

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

# ===== STRICT PRE-FLIGHT CHECKS =====
# These checks ensure the loop will actually work before starting

INSTALL_TS_FILE="$HOME/.claude/ralph-hooks-installed-at"

# 1. Check if hooks were installed after session started (restart detection)
if [[ -f "$INSTALL_TS_FILE" ]]; then
    INSTALL_TS=$(cat "$INSTALL_TS_FILE")
    # Use .claude dir mtime as session start proxy
    SESSION_TS=$(stat -f %m "$HOME/.claude" 2>/dev/null || stat -c %Y "$HOME/.claude" 2>/dev/null || echo "0")
    # Also check projects dir
    if [[ -d "$HOME/.claude/projects" ]]; then
        PROJECTS_TS=$(stat -f %m "$HOME/.claude/projects" 2>/dev/null || stat -c %Y "$HOME/.claude/projects" 2>/dev/null || echo "0")
        if [[ "$PROJECTS_TS" -gt "$SESSION_TS" ]]; then
            SESSION_TS="$PROJECTS_TS"
        fi
    fi

    if [[ "$INSTALL_TS" -gt "$SESSION_TS" ]]; then
        echo "ERROR: Hooks were installed AFTER this session started!"
        echo ""
        echo "The Stop hook won't run until you restart Claude Code."
        echo "Installed at: $(date -r "$INSTALL_TS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$INSTALL_TS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
        echo ""
        echo "ACTION: Exit and restart Claude Code, then run /ralph:start again"
        exit 1
    fi
fi

# 2. Verify uv is available (required for Stop hook)
if ! command -v uv &>/dev/null; then
    echo "ERROR: 'uv' is required but not installed."
    echo ""
    echo "The Stop hook uses 'uv run' to execute loop-until-done.py"
    echo ""
    echo "Install with: brew install uv"
    exit 1
fi

# 3. Verify Python 3.11+ (required for Stop hook)
PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")
if [[ -n "$PY_VERSION" ]]; then
    PY_MAJOR="${PY_VERSION%%.*}"
    PY_MINOR="${PY_VERSION#*.}"
    if [[ "$PY_MAJOR" -lt 3 ]] || [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ]]; then
        echo "ERROR: Python 3.11+ required (found: $PY_VERSION)"
        echo ""
        echo "The Stop hook uses Python 3.11+ features."
        echo ""
        echo "Upgrade with: brew upgrade python@3.11"
        exit 1
    fi
else
    echo "ERROR: Python not found"
    echo ""
    echo "Install with: brew install python@3.11"
    exit 1
fi

# 4. Verify jq is available (required for config management)
if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is required but not installed."
    echo ""
    echo "Install with: brew install jq"
    exit 1
fi

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

# Detect --skip-constraint-scan flag (v3.0.0+)
SKIP_CONSTRAINT_SCAN=false
if [[ "$ARGS" == *"--skip-constraint-scan"* ]]; then
    SKIP_CONSTRAINT_SCAN=true
    ARGS="${ARGS//--skip-constraint-scan/}"
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

# Preserve existing guidance from previous session (if any)
# This ensures /ralph:encourage and /ralph:forbid directives persist across restarts
EXISTING_GUIDANCE='{}'
if [[ -f "$PROJECT_DIR/.claude/ralph-config.json" ]]; then
    EXISTING_GUIDANCE=$(jq '.guidance // {}' "$PROJECT_DIR/.claude/ralph-config.json" 2>/dev/null || echo '{}')
fi

# Generate unified ralph-config.json (v3.0.0 schema - Pydantic migration)
CONFIG_JSON=$(jq -n \
    --arg state "running" \
    --argjson poc_mode "$POC_MODE" \
    --argjson production_mode "$PRODUCTION_MODE" \
    --argjson no_focus "$NO_FOCUS" \
    --argjson skip_constraint_scan "$SKIP_CONSTRAINT_SCAN" \
    --arg target_file "$TARGET_FILE" \
    --arg task_prompt "$TASK_PROMPT" \
    --argjson min_hours "$MIN_HOURS" \
    --argjson max_hours "$MAX_HOURS" \
    --argjson min_iterations "$MIN_ITERS" \
    --argjson max_iterations "$MAX_ITERS" \
    --argjson existing_guidance "$EXISTING_GUIDANCE" \
    '{
        version: "3.0.0",
        state: $state,
        poc_mode: $poc_mode,
        production_mode: $production_mode,
        no_focus: $no_focus,
        skip_constraint_scan: $skip_constraint_scan,
        loop_limits: {
            min_hours: $min_hours,
            max_hours: $max_hours,
            min_iterations: $min_iterations,
            max_iterations: $max_iterations
        }
    }
    + (if $target_file != "" then {target_file: $target_file} else {} end)
    + (if $task_prompt != "" then {task_prompt: $task_prompt} else {} end)
    + (if $existing_guidance != {} then {guidance: $existing_guidance} else {} end)'
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
ADAPTER_NAME=""
if [[ -d "$HOOKS_DIR" ]]; then
    ADAPTER_NAME=$(cd "$HOOKS_DIR" && python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '.')
try:
    from core.registry import AdapterRegistry
    AdapterRegistry.discover(Path('adapters'))
    adapter = AdapterRegistry.get_adapter(Path('$PROJECT_DIR'))
    if adapter:
        print(adapter.name)
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null || echo "")
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
if [[ "$ADAPTER_NAME" == "alpha-forge" ]]; then
    echo "Adapter: alpha-forge"
    echo "  → Expert-synthesis convergence (WFE, diminishing returns, patience)"
    echo "  → Reads metrics from outputs/runs/*/summary.json"
else
    echo "⚠️  WARNING: Not an Alpha Forge project"
    echo "  → Ralph hooks will SKIP this project (v8.0.2+)"
    echo "  → Ralph is designed exclusively for Alpha Forge ML workflows"
    echo "  → Detection: pyproject.toml, packages/alpha-forge-core/, outputs/runs/"
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
