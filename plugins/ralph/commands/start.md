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

**Purpose**: Detect environment constraints before loop starts. Results inform Ralph behavior.

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

# Run scanner - discover UV with same fallback pattern as main script
UV_CMD=""
discover_uv() {
    command -v uv &>/dev/null && echo "uv" && return 0
    for loc in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" "/opt/homebrew/bin/uv" "/usr/local/bin/uv" "$HOME/.local/share/mise/shims/uv"; do
        [[ -x "$loc" ]] && echo "$loc" && return 0
    done
    # Dynamic mise version discovery
    local mise_base="$HOME/.local/share/mise/installs/uv"
    if [[ -d "$mise_base" ]]; then
        local ver=$(ls -1 "$mise_base" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$ver" ]]; then
            local plat=$(ls -1 "$mise_base/$ver" 2>/dev/null | head -1)
            [[ -n "$plat" && -x "$mise_base/$ver/$plat/uv" ]] && echo "$mise_base/$ver/$plat/uv" && return 0
            [[ -x "$mise_base/$ver/uv" ]] && echo "$mise_base/$ver/uv" && return 0
        fi
    fi
    command -v mise &>/dev/null && mise which uv &>/dev/null 2>&1 && echo "mise exec -- uv" && return 0
    return 1
}
UV_CMD=$(discover_uv) || { echo "Constraint scan: SKIPPED (uv not found)"; exit 0; }

echo "Running constraint scanner..."
SCAN_OUTPUT=$($UV_CMD run -q "$SCANNER_SCRIPT" --project "$PROJECT_DIR" 2>&1)
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

    # Save results for AUQ to read (NDJSON format with .jsonl extension)
    mkdir -p "$PROJECT_DIR/.claude"
    echo "$SCAN_OUTPUT" > "$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"
else
    echo "Constraint scan: WARNING (scanner returned exit code $SCAN_EXIT)"
    echo "$SCAN_OUTPUT" | head -5
fi
CONSTRAINT_SCAN_SCRIPT
```

If the scanner exits with code 2 (critical constraints), stop and inform user.

## Step 1.4.5: Explore-Based Constraint Discovery (Parallel Agents)

**Purpose**: Spawn multiple Explore subagents to discover constraints the static scanner cannot detect.

**MANDATORY: Execute NOW before proceeding to Step 1.5**

Claude MUST spawn exactly 5 Task tools in a single message with these parameters:

### MANDATORY Task 1: Project Memory & Philosophy Constraints

```
Task tool parameters:
  description: "Analyze project memory constraints"
  subagent_type: "Explore"
  run_in_background: true
  prompt: |
    DEEP DIVE into project memory files to discover constraints on Claude's degrees of freedom.

    READ THESE FILES FIRST:
    - CLAUDE.md (project instructions, philosophy, forbidden patterns)
    - .claude/ directory (memories, settings, project-specific config)
    - ROADMAP.md (P0/P1 priorities, explicit scope limits)
    - docs/adr/ (Architecture Decision Records - past decisions that constrain future work)

    Extract constraints like:
    - "Do NOT modify X" instructions
    - Philosophy rules (e.g., "prefer simplicity over features")
    - Explicit forbidden patterns mentioned in project memory
    - Scope limits from ROADMAP (what's explicitly out of scope)

    Return NDJSON: {"source":"agent-memory","severity":"CRITICAL|HIGH|MEDIUM","description":"...","file":"...","recommendation":"Ralph should avoid..."}
```

### MANDATORY Task 2: Architecture & Coupling Constraints

```
Task tool parameters:
  description: "Analyze architectural constraints"
  subagent_type: "Explore"
  run_in_background: true
  prompt: |
    Analyze architectural patterns that constrain safe modification.

    READ THESE FILES:
    - pyproject.toml, setup.py (package structure, entry points)
    - Core module __init__.py files (public API surface)
    - docs/adr/ (past architectural decisions)

    Focus on:
    - Circular imports, tightly coupled modules
    - Public API that cannot change without breaking users
    - Package structure assumptions
    - Cross-layer dependencies

    Return NDJSON: {"source":"agent-arch","severity":"HIGH|MEDIUM|LOW","description":"...","modules":["A","B"],"recommendation":"..."}
```

### MANDATORY Task 3: Research Session Lessons Learned

```
Task tool parameters:
  description: "Extract research session constraints"
  subagent_type: "Explore"
  run_in_background: true
  prompt: |
    Analyze past research sessions to find lessons learned and forbidden patterns.

    READ THESE FILES:
    - outputs/research_sessions/*/research_summary.md
    - outputs/research_sessions/*/research_log.md (if exists)
    - Any "lessons_learned" or "warnings" sections

    Extract:
    - Failed experiments (don't repeat these)
    - Hyperparameter ranges that caused issues
    - Strategies that were abandoned and why
    - Explicit warnings from past sessions

    Return NDJSON: {"source":"agent-research","severity":"HIGH|MEDIUM","description":"Past session found: ...","session":"...","recommendation":"Avoid..."}
```

### MANDATORY Task 4: Testing & Validation Constraints

```
Task tool parameters:
  description: "Find testing constraints"
  subagent_type: "Explore"
  run_in_background: true
  prompt: |
    Find testing gaps and validation requirements that constrain safe changes.

    READ THESE FILES:
    - tests/ directory structure
    - pytest.ini, pyproject.toml [tool.pytest] section
    - CI/CD workflows (.github/workflows/)

    Focus on:
    - Modules with zero test coverage (risky to modify)
    - Integration tests that must pass
    - Validation thresholds (e.g., min Sharpe ratio, max drawdown)
    - Pre-commit hooks and their requirements

    Return NDJSON: {"source":"agent-testing","severity":"HIGH|MEDIUM|LOW","description":"...","location":"...","recommendation":"..."}
```

### MANDATORY Task 5: Degrees of Freedom Analysis

```
Task tool parameters:
  description: "Analyze degrees of freedom"
  subagent_type: "Explore"
  run_in_background: true
  prompt: |
    Find explicit and implicit limits on what Ralph can explore.

    READ THESE FILES:
    - CLAUDE.md (explicit instructions)
    - .claude/ralph-config.json (previous session guidance)
    - Config files (*.yaml, *.toml) for hardcoded limits

    Focus on:
    - Hard gates (if not X, skip silently)
    - One-way state transitions
    - Configuration that cannot be overridden at runtime
    - Feature flags and their current state
    - Escape hatches (--skip-X flags, override mechanisms)

    Return NDJSON: {"source":"agent-freedom","severity":"CRITICAL|HIGH|MEDIUM","description":"...","gate":"...","recommendation":"..."}
```

**Execution**: Spawn ALL 5 Task tools in a SINGLE message (parallel execution). Use `run_in_background: true`.

---

## Step 1.4.6: BLOCKING GATE - Collect Agent Results

**⛔ MANDATORY: Do NOT proceed to Step 1.5 until this gate passes**

Claude MUST execute these TaskOutput calls with `block: true`:

```
For EACH agent spawned in Step 1.4.5:
  TaskOutput(task_id: "<agent_id>", block: true, timeout: 30000)
```

**Wait for ALL 5 agents** (or timeout after 30s each). Extract NDJSON constraints from each agent's output.

**Merge agent findings** into constraint scan file:

```bash
/usr/bin/env bash << 'AGENT_MERGE_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCAN_FILE="$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"

# Claude MUST append each agent's NDJSON findings here:
# For each constraint JSON from agent output:
#   echo '{"_type":"constraint","source":"agent-env","severity":"HIGH","description":"..."}' >> "$SCAN_FILE"

echo "=== AGENT FINDINGS MERGED ==="
echo "Constraints in scan file:"
wc -l < "$SCAN_FILE" 2>/dev/null || echo "0"
AGENT_MERGE_SCRIPT
```

**Gate verification**: Before proceeding, confirm:
- [ ] All 5 TaskOutput calls completed (or timed out)
- [ ] Agent findings appended to `.claude/ralph-constraint-scan.jsonl`
- [ ] Can proceed to Step 1.5

**If timeout on some agents**: Proceed with available results. Log which agents timed out.

---

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

### 1.6.2: Binary Keep/Reconfigure (Conditional)

**If `GUIDANCE_EXISTS == "true"`:**

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

**If `GUIDANCE_EXISTS == "false"` (first run):**

Proceed directly to Step 1.6.2.5 to load constraint scan results. No user prompt needed.

### 1.6.2.5: Load Constraint Scan Results (NDJSON Output with Learned Filtering)

**Purpose**: Load constraint scan results in NDJSON format, filtering out previously acknowledged constraints.

**Learned behavior**: Constraints the user previously selected as "forbidden" are stored in `.claude/ralph-acknowledged-constraints.jsonl` and filtered from future displays.

Run the following bash script to output constraints in NDJSON (one JSON object per line):

```bash
/usr/bin/env bash << 'LOAD_SCAN_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCAN_FILE="$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"
ACK_FILE="$PROJECT_DIR/.claude/ralph-acknowledged-constraints.jsonl"

if [[ -f "$SCAN_FILE" ]]; then
    # Load acknowledged constraint IDs (if file exists)
    ACKNOWLEDGED_IDS=""
    if [[ -f "$ACK_FILE" ]]; then
        ACKNOWLEDGED_IDS=$(jq -r 'select(._type == "constraint") | .id' "$ACK_FILE" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
        ACK_COUNT=$(grep -c '"_type":"constraint"' "$ACK_FILE" 2>/dev/null || echo "0")
        echo "=== ACKNOWLEDGED CONSTRAINTS ==="
        echo "Previously acknowledged: $ACK_COUNT constraints (filtered from display)"
        echo ""
    fi

    # NDJSON format: each line is a JSON object with _type field
    # Filter out acknowledged constraints and count by severity
    if [[ -n "$ACKNOWLEDGED_IDS" ]]; then
        # Filter constraints from NDJSON (lines with _type=constraint that don't match acknowledged IDs)
        FILTERED=$(grep '"_type":"constraint"' "$SCAN_FILE" 2>/dev/null | \
            jq -c --arg ack_pattern "$ACKNOWLEDGED_IDS" 'select(.id | test($ack_pattern) | not)' 2>/dev/null)
    else
        FILTERED=$(grep '"_type":"constraint"' "$SCAN_FILE" 2>/dev/null)
    fi

    # Count by severity (from filtered NDJSON lines)
    CRITICAL_COUNT=$(echo "$FILTERED" | jq -s '[.[] | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
    HIGH_COUNT=$(echo "$FILTERED" | jq -s '[.[] | select(.severity == "high")] | length' 2>/dev/null || echo "0")
    MEDIUM_COUNT=$(echo "$FILTERED" | jq -s '[.[] | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
    LOW_COUNT=$(echo "$FILTERED" | jq -s '[.[] | select(.severity == "low")] | length' 2>/dev/null || echo "0")
    TOTAL_COUNT=$((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))
    BUSYWORK_COUNT=$(grep -c '"_type":"busywork"' "$SCAN_FILE" 2>/dev/null || echo "0")

    echo "=== CONSTRAINT SCAN SUMMARY ==="
    echo "SEVERITY_COUNTS: critical=$CRITICAL_COUNT high=$HIGH_COUNT medium=$MEDIUM_COUNT low=$LOW_COUNT total=$TOTAL_COUNT"
    echo "BUSYWORK_COUNT: $BUSYWORK_COUNT"
    echo ""
    echo "=== CONSTRAINTS (NDJSON) ==="
    # Output each FILTERED constraint as NDJSON (already one JSON per line)
    echo "$FILTERED"
    echo ""
    echo "=== BUSYWORK CATEGORIES (NDJSON) ==="
    grep '"_type":"busywork"' "$SCAN_FILE" 2>/dev/null
    echo ""
    echo "=== END SCAN RESULTS ==="
else
    echo "=== CONSTRAINT SCAN SUMMARY ==="
    echo "SEVERITY_COUNTS: critical=0 high=0 medium=0 low=0 total=0"
    echo "BUSYWORK_COUNT: 0"
    echo "=== NO SCAN FILE FOUND ==="
fi
LOAD_SCAN_SCRIPT
```

**Claude MUST parse this output**:

1. **Extract severity counts** from `SEVERITY_COUNTS:` line for question text
2. **Parse NDJSON constraints** between `=== CONSTRAINTS (NDJSON) ===` and `=== BUSYWORK CATEGORIES ===`
3. **Parse NDJSON busywork** between `=== BUSYWORK CATEGORIES (NDJSON) ===` and `=== END SCAN RESULTS ===`
4. **Build dynamic AUQ options** with constraint-derived items first, then static fallbacks

**NDJSON constraint format** (one per line):
```json
{"id":"hardcoded-001","severity":"high","category":"hardcoded_path","description":"Hardcoded path: /Users/terryli/...","file":"pyproject.toml","line":15,"recommendation":"Use environment variable"}
```

### 1.6.3: Forbidden Items (multiSelect, DYNAMIC)

**MANDATORY: Build options dynamically from Step 1.6.2.5 output**

**AUQ Limit**: Maximum 4 options total. Priority order:
1. CRITICAL severity constraints (up to 2)
2. HIGH severity constraints (up to 2)
3. If <4 constraint options, fill with static categories

**Algorithm** - Claude MUST execute this logic:

```
Step 1: Parse severity counts from SEVERITY_COUNTS line
  - Extract: critical=N, high=M, total=T

Step 2: Build constraint options (max 4, severity priority)
  options = []

  # First: CRITICAL constraints (max 2)
  for each NDJSON line where severity == "critical":
    if len(options) >= 2: break
    options.append({
      label: description[:55] + "..." if len > 55 else description,
      description: "(CRITICAL) " + file + ":" + line + " - " + recommendation[:40]
    })

  # Second: HIGH constraints (max 2 more)
  for each NDJSON line where severity == "high":
    if len(options) >= 4: break
    options.append({
      label: description[:55] + "..." if len > 55 else description,
      description: "(HIGH) " + file + ":" + line + " - " + recommendation[:40]
    })

  # Third: Fill remaining with static categories
  static_categories = ["Documentation updates", "Dependency upgrades", "Refactoring", "CI/CD modifications"]
  while len(options) < 4 and static_categories:
    options.append(static_categories.pop(0))

Step 3: Build question text
  if critical > 0 or high > 0:
    question = "What should Ralph avoid? ({critical} critical, {high} high detected)"
  else:
    question = "What should Ralph avoid? (no high-severity constraints)"
```

**Example transformation**:

NDJSON input:
```
{"severity":"critical","description":"Hardcoded API key in config.py","file":"config.py","line":42,"recommendation":"Move to env var"}
{"severity":"high","description":"Circular import: core ↔ utils","file":"core.py","line":1,"recommendation":"Extract interface"}
```

Becomes AUQ options:
```yaml
options:
  - label: "Hardcoded API key in config.py"
    description: "(CRITICAL) config.py:42 - Move to env var"
  - label: "Circular import: core ↔ utils"
    description: "(HIGH) core.py:1 - Extract interface"
  - label: "Documentation updates"
    description: "README, CHANGELOG, docstrings, comments"
  - label: "Dependency upgrades"
    description: "Version bumps, renovate PRs, package updates"
```

Use AskUserQuestion with the dynamically built options above.

**Static fallback categories** (used when no constraints or to fill remaining slots):
- "Documentation updates" - "README, CHANGELOG, docstrings, comments"
- "Dependency upgrades" - "Version bumps, renovate PRs, package updates"
- "Refactoring" - "Code restructuring without behavior change"
- "CI/CD modifications" - "Workflow files, GitHub Actions, pipelines"

**If total=0**: Show only 4 static categories with question `"What should Ralph avoid? (no constraints detected)"`

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

- question: "What should Ralph prioritize? (Select all that apply)"
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

### 1.6.7: Update Config (EXECUTE with Post-Write Validation + Learned Behavior)

**IMPORTANT**: After collecting responses from Steps 1.6.3-1.6.6, you MUST:
1. Write guidance to config WITH validation
2. Append constraint-derived selections to `.jsonl` for learned filtering

1. **Collect responses** from the AUQ steps above:
   - `FORBIDDEN_ITEMS`: Selected labels from 1.6.3 + custom items from 1.6.4 (if any)
   - `ENCOURAGED_ITEMS`: Selected labels from 1.6.5 + custom items from 1.6.6 (if any)
   - `SELECTED_CONSTRAINT_IDS`: IDs of constraint-derived options user selected (from NDJSON parsing)

2. **Write to config with post-write validation** using the Bash tool (substitute actual values):

```bash
/usr/bin/env bash << 'GUIDANCE_WRITE_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"
SCAN_FILE="$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"
ACK_FILE="$PROJECT_DIR/.claude/ralph-acknowledged-constraints.jsonl"
BACKUP_FILE="${CONFIG_FILE}.backup"

# Substitute these with actual AUQ responses:
FORBIDDEN_JSON='["Documentation updates", "Dependency upgrades"]'  # From 1.6.3 + 1.6.4
ENCOURAGED_JSON='["ROADMAP P0 items", "Research experiments"]'     # From 1.6.5 + 1.6.6

# Substitute with constraint IDs user selected (from NDJSON constraint options)
# Format: space-separated list of constraint IDs that user selected as forbidden
SELECTED_CONSTRAINT_IDS="hardcoded-001 hardcoded-002"  # From 1.6.3 constraint-derived selections

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Load constraint scan data (if exists) for persistence
# Convert NDJSON to structured JSON for config storage
CONSTRAINT_SCAN_JSON='null'
if [[ -f "$SCAN_FILE" ]]; then
    # Parse NDJSON: extract metadata, constraints, and busywork into structured JSON
    METADATA=$(grep '"_type":"metadata"' "$SCAN_FILE" 2>/dev/null | head -1)
    CONSTRAINTS=$(grep '"_type":"constraint"' "$SCAN_FILE" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')
    BUSYWORK=$(grep '"_type":"busywork"' "$SCAN_FILE" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')

    # Build structured JSON from NDJSON components
    CONSTRAINT_SCAN_JSON=$(jq -n \
        --argjson metadata "$METADATA" \
        --argjson constraints "$CONSTRAINTS" \
        --argjson busywork "$BUSYWORK" \
        '{
            scan_timestamp: $metadata.scan_timestamp,
            project_dir: $metadata.project_dir,
            worktree_type: $metadata.worktree_type,
            constraints: $constraints,
            builtin_busywork: $busywork
        }' 2>/dev/null || echo 'null')
fi

# Create backup before write (for rollback)
mkdir -p "$PROJECT_DIR/.claude"
if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

# Write config (guidance + constraint_scan)
if [[ -f "$CONFIG_FILE" ]]; then
    jq --argjson forbidden "$FORBIDDEN_JSON" \
       --argjson encouraged "$ENCOURAGED_JSON" \
       --arg timestamp "$TIMESTAMP" \
       --argjson constraint_scan "$CONSTRAINT_SCAN_JSON" \
       '.guidance = {forbidden: $forbidden, encouraged: $encouraged, timestamp: $timestamp} | .constraint_scan = $constraint_scan' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
    jq -n --argjson forbidden "$FORBIDDEN_JSON" \
          --argjson encouraged "$ENCOURAGED_JSON" \
          --arg timestamp "$TIMESTAMP" \
          --argjson constraint_scan "$CONSTRAINT_SCAN_JSON" \
          '{version: "3.0.0", guidance: {forbidden: $forbidden, encouraged: $encouraged, timestamp: $timestamp}, constraint_scan: $constraint_scan}' \
          > "$CONFIG_FILE"
fi

# === LEARNED BEHAVIOR: Append to .jsonl ===
# Append newly selected constraint IDs to acknowledged constraints file (NDJSON format)
if [[ -n "$SELECTED_CONSTRAINT_IDS" && -f "$SCAN_FILE" ]]; then
    for CONSTRAINT_ID in $SELECTED_CONSTRAINT_IDS; do
        # Check if already acknowledged (avoid duplicates)
        if [[ -f "$ACK_FILE" ]] && grep -q "\"id\":\"$CONSTRAINT_ID\"" "$ACK_FILE" 2>/dev/null; then
            continue  # Already acknowledged, skip
        fi
        # Get constraint details from NDJSON scan file and append to ack file
        # NDJSON format: each line is a JSON object, grep for the matching ID
        CONSTRAINT_DATA=$(grep "\"id\":\"$CONSTRAINT_ID\"" "$SCAN_FILE" 2>/dev/null | head -1 | \
            jq -c --arg ts "$TIMESTAMP" '. + {acknowledged_at: $ts}' 2>/dev/null)
        if [[ -n "$CONSTRAINT_DATA" ]]; then
            echo "$CONSTRAINT_DATA" >> "$ACK_FILE"
        fi
    done
    NEW_ACK_COUNT=$(echo "$SELECTED_CONSTRAINT_IDS" | wc -w | tr -d ' ')
    echo "=== LEARNED BEHAVIOR ==="
    echo "Appended $NEW_ACK_COUNT constraint(s) to $ACK_FILE"
    echo "These will be filtered from future constraint displays."
    echo ""
fi

# === POST-WRITE VALIDATION ===
validate_config() {
    local file="$1"

    # Check 1: File exists and readable
    [[ -f "$file" && -r "$file" ]] || return 1

    # Check 2: Valid JSON (jq can parse it)
    jq empty "$file" >/dev/null 2>&1 || return 2

    # Check 3: Required fields present
    jq -e '.guidance.forbidden and .guidance.encouraged and .guidance.timestamp' "$file" >/dev/null 2>&1 || return 3

    # Check 4: Arrays are valid (forbidden/encouraged are arrays of strings)
    jq -e '.guidance.forbidden | type == "array"' "$file" >/dev/null 2>&1 || return 4
    jq -e '.guidance.encouraged | type == "array"' "$file" >/dev/null 2>&1 || return 5

    return 0
}

if validate_config "$CONFIG_FILE"; then
    echo "✓ Guidance + constraint_scan saved to $CONFIG_FILE"
    echo ""
    echo "=== VALIDATION PASSED ==="
    jq '{guidance: .guidance, constraint_scan_timestamp: .constraint_scan.scan_timestamp}' "$CONFIG_FILE"
    # Cleanup backup on success
    rm -f "$BACKUP_FILE"
else
    VALIDATION_ERROR=$?
    echo "✗ VALIDATION FAILED (error code: $VALIDATION_ERROR)"
    echo ""
    echo "=== ROLLING BACK ==="
    if [[ -f "$BACKUP_FILE" ]]; then
        mv "$BACKUP_FILE" "$CONFIG_FILE"
        echo "Restored previous config from backup"
    else
        rm -f "$CONFIG_FILE"
        echo "Removed invalid config (no backup existed)"
    fi
    echo ""
    echo "Error codes: 1=missing, 2=invalid JSON, 3=missing fields, 4=forbidden not array, 5=encouraged not array"
    exit 1
fi
GUIDANCE_WRITE_SCRIPT
```

**Execution model**: Claude interprets Steps 1.6.3-1.6.6 (uses AskUserQuestion tool), collects responses, then runs the bash script above with actual values substituted.

**Key substitutions Claude MUST make**:
- `FORBIDDEN_JSON`: Array of selected forbidden labels
- `ENCOURAGED_JSON`: Array of selected encouraged labels
- `SELECTED_CONSTRAINT_IDS`: Space-separated list of constraint IDs from NDJSON options user selected

Post-write validation ensures config integrity with automatic rollback on failure. Learned behavior appends acknowledged constraints to `.jsonl` for future filtering.

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

# ===== UV DISCOVERY =====
# Robust UV detection with multi-level fallback (matches canonical cc-skills pattern)
# Returns UV command (path or "mise exec -- uv") on stdout, exits 1 if not found
UV_CMD=""
discover_uv() {
    # Priority 1: Already in PATH (shell configured, Homebrew, direct install)
    if command -v uv &>/dev/null; then
        echo "uv"
        return 0
    fi

    # Priority 2: Common direct installation locations
    local uv_locations=(
        "$HOME/.local/bin/uv"                           # Official curl installer
        "$HOME/.cargo/bin/uv"                           # cargo install
        "/opt/homebrew/bin/uv"                          # Homebrew Apple Silicon
        "/usr/local/bin/uv"                             # Homebrew Intel / manual
        "$HOME/.local/share/mise/shims/uv"              # mise shims
        "$HOME/.local/share/mise/installs/uv/latest/uv" # mise direct
    )

    for loc in "${uv_locations[@]}"; do
        if [[ -x "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    # Priority 3: Find mise-installed uv dynamically (version directories)
    local mise_uv_base="$HOME/.local/share/mise/installs/uv"
    if [[ -d "$mise_uv_base" ]]; then
        local latest_version
        latest_version=$(ls -1 "$mise_uv_base" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$latest_version" ]]; then
            # Handle nested platform directory (e.g., uv-aarch64-apple-darwin/uv)
            local platform_dir
            platform_dir=$(ls -1 "$mise_uv_base/$latest_version" 2>/dev/null | head -1)
            if [[ -n "$platform_dir" && -x "$mise_uv_base/$latest_version/$platform_dir/uv" ]]; then
                echo "$mise_uv_base/$latest_version/$platform_dir/uv"
                return 0
            fi
            # Direct binary
            if [[ -x "$mise_uv_base/$latest_version/uv" ]]; then
                echo "$mise_uv_base/$latest_version/uv"
                return 0
            fi
        fi
    fi

    # Priority 4: Use mise exec as fallback
    if command -v mise &>/dev/null && mise which uv &>/dev/null 2>&1; then
        echo "mise exec -- uv"
        return 0
    fi

    return 1
}

# Discover UV once at script start
if ! UV_CMD=$(discover_uv); then
    echo "ERROR: 'uv' is required but not installed."
    echo ""
    echo "The Stop hook uses 'uv run' to execute loop-until-done.py"
    echo ""
    echo "Searched locations:"
    echo "  - PATH (command -v uv)"
    echo "  - \$HOME/.local/bin/uv"
    echo "  - /opt/homebrew/bin/uv"
    echo "  - \$HOME/.local/share/mise/shims/uv"
    echo "  - \$HOME/.local/share/mise/installs/uv/*/..."
    echo ""
    echo "Install with one of:"
    echo "  • curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "  • brew install uv"
    echo "  • mise use -g uv@latest"
    exit 1
fi

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

# 2. UV already verified by discover_uv() above - display discovered path
echo "UV detected: $UV_CMD"

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

Ralph is **supplementary** to alpha-forge's `/research`:

- `/research` owns the inner loop (5 iterations, 5 expert subagents)
- Ralph owns the outer loop (session-to-session learning, OODA decisions)

**Do NOT ask the user what to work on.** Proceed autonomously through OODA.
