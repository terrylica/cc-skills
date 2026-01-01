# Explore Agent Integration Design for Ralph

**Status**: Proposal (Design Phase)
**Date**: 2025-12-31
**Related ADR**: [ADR: Ralph Constraint Scanning](/docs/adr/2025-12-29-ralph-constraint-scanning.md)
**Scope**: Integration of parallel Explore agents into `/ralph:start` AUQ flow for constraint discovery

## Executive Summary

This document describes how Explore agents (Claude Code's native capability for autonomous discovery) would integrate with Ralph's existing constraint-scanner findings to provide a **richer, context-aware constraint discovery flow** in the `/ralph:start` AUQ cascade.

**Key Design Decision**: Explore agents augment, not replace, the static constraint-scanner. Both sources contribute to a unified AUQ question for guidance configuration.

---

## Current State Analysis

### Constraint-Scanner Pipeline (v9.2.0+)

```
/ralph:start invoked
    ↓
Step 1.4: Run constraint-scanner.py
    ↓
Output: .claude/ralph-constraint-scan.jsonl (NDJSON format)
    ├─ Metadata (scan timestamp, project type, etc.)
    ├─ Constraint lines (id, severity, category, file:line, recommendation)
    └─ Busywork categories (lint, docs, types, etc.)
    ↓
Step 1.6.2.5: Load scan results
    ├─ Filter previously acknowledged constraints
    ├─ Count by severity
    └─ Output NDJSON for AUQ parsing
    ↓
Step 1.6.3-1.6.6: AUQ Questions
    ├─ Forbidden (constraint-derived + static categories + custom)
    ├─ Encouraged (static list + custom)
    └─ Post-write validation & learned behavior
```

**Current Scanner Scope** (static file analysis):
- Hardcoded absolute paths in `.claude/`, `pyproject.toml`, etc.
- Rigid directory structure assumptions
- Global hook conflicts

**Limitations**:
- No awareness of runtime/execution environment
- No knowledge of project-specific patterns
- Single point of failure (if scanner is slow or fails)
- No context about imported dependencies or configuration issues

---

## Proposed Enhancement: Explore Agent Integration

### Overview

```
/ralph:start invoked
    ↓
Step 1.4: Parallel Discovery Phase
    ├─ Constraint-Scanner (existing)
    │  └─ File system constraints, hooks, paths
    │
    └─ [NEW] Explore Agents (parallel)
       ├─ Agent 1: Environment/Dependency Scanner
       │  └─ Python imports, uv.lock, constraint violations
       ├─ Agent 2: Configuration Discovery
       │  └─ .toml/.yaml/.json parsing, missing configs
       └─ Agent 3: Integration Points
          └─ External services, APIs, auth requirements
    ↓
Step 1.4.5: [NEW] Aggregate Findings
    ├─ Merge NDJSON from scanner + agents
    ├─ Dedup by constraint ID
    ├─ Normalize severity levels
    └─ Sort by impact
    ↓
Step 1.6.2.5: Load Aggregated Results (Enhanced)
    ├─ NDJSON now includes agent-discovered constraints
    ├─ Severity distribution includes agent findings
    └─ Learned behavior applies to all sources
    ↓
Step 1.6.3-1.6.6: AUQ Questions (Unified)
    └─ Same flow, now with richer constraint options
```

---

## Design Details

### 1. Explore Agent Protocol

Each Explore agent operates independently and returns findings in a **canonical constraint JSON format**:

```python
# Agent output format (one constraint per line, newline-separated JSON)
{
    "agent_id": "env-scanner",           # Unique per agent
    "constraint_id": "agent-env-001",    # "agent-{scope}-{seq}"
    "severity": "high",                  # critical|high|medium|low
    "category": "dependency_conflict",   # Namespace constraints by category
    "description": "uv.lock mismatch: Python 3.11 required but 3.10 detected",
    "source_file": "uv.lock",            # Where this was discovered
    "source_line": 42,                   # Line number (0 if N/A)
    "affected_scope": "python-runtime",  # What aspect of Ralph does this affect
    "recommendation": "Upgrade Python to 3.11+ or pin uv.lock for 3.10",
    "resolution_steps": [                # Optional: multi-step resolution
        "Check current Python version: python3 --version",
        "Upgrade: brew install python@3.11 or pyenv local 3.11",
        "Regenerate: uv lock --upgrade"
    ],
    "tags": ["runtime", "python", "uv"]  # For filtering/grouping
}
```

**Key Properties**:
- `agent_id`: Identifies which agent discovered this (for deduplication)
- `constraint_id`: Unique within agent + across agents (using prefix)
- `affected_scope`: Clarifies what Ralph function this impacts
- `resolution_steps`: Actionable, reducing cognitive load in AUQ

### 2. Agent Specifications

#### Agent 1: Environment/Dependency Scanner

**Purpose**: Check Python runtime, dependencies, lock file state

**Constraints Detected**:
- Python version mismatches (required vs. installed)
- `uv.lock` out of date with `pyproject.toml`
- Missing optional dependencies for Ralph (e.g., `pydantic`, `filelock`)
- Virtual environment issues
- `pip` vs `uv` inconsistency

**Execution**:
```bash
# Pseudo-code - Claude Code would implement as Python script
discover_uv() → detect uv version
python3 --version → check Python version
uv lock --dry-run → detect out-of-date lock
grep -r "requires-python" → parse version constraints
cat pyproject.toml | jq '.dependencies' → check for missing deps
```

**Expected Output**: 3-5 constraints, 2-10 seconds runtime

#### Agent 2: Configuration Discovery

**Purpose**: Scan all configuration files for incompatible settings

**Constraints Detected**:
- `.claude/settings.json` conflicts with Ralph hooks
- Missing `.claude/ralph-config.json` (first run)
- Incompatible `mise.toml` environment variables
- Environment variable pollution from shell rc files
- Feature flags in global config affecting project

**Execution**:
```bash
# Parse .claude/settings.json for hook registry
jq '.hooks' ~/.claude/settings.json

# Check for ralph-config.json
test -f .claude/ralph-config.json

# Validate mise.toml syntax
mise sync  # Will error if invalid

# Source shell rc to detect env var pollution
env | grep -E "(PYTHONPATH|PYTHONHOME|PATH|HOME)"
```

**Expected Output**: 2-4 constraints, 1-3 seconds runtime

#### Agent 3: Integration Points

**Purpose**: Detect external dependencies and authentication requirements

**Constraints Detected**:
- Missing GitHub token (for git operations in loop)
- Missing Doppler/1Password secrets
- Unconfigured SSH keys (for remote execution)
- API rate limits (if hitting external APIs)
- Network connectivity issues
- Missing tools in PATH (git, jq, fd, rg, etc.)

**Execution**:
```bash
# Check for auth tokens
gh auth status  # GitHub CLI
doppler auth status  # Doppler

# Verify tools in PATH
for tool in git jq fd rg; do
    command -v $tool || echo "Missing: $tool"
done

# Network connectivity
curl -s https://api.github.com --max-time 2 | head

# Check SSH keys
ssh-add -l  # List loaded keys
```

**Expected Output**: 1-4 constraints, 3-5 seconds runtime

---

### 3. Aggregation Algorithm

**Step 1.4.5 in start.md** - Parallel execution + merge:

```bash
#!/usr/bin/env bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCAN_FILE="$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"
AGENT_RESULTS="$PROJECT_DIR/.claude/ralph-agent-findings.jsonl"

# Run constraint-scanner (existing)
echo "Running constraint-scanner..."
SCANNER_OUTPUT=$(uv run constraint-scanner.py --project "$PROJECT_DIR" 2>&1)

# [NEW] Spawn 3 agents in parallel
echo "Spawning Explore agents..."
(
    # Agent 1: Environment Scanner
    python3 agent_env_scanner.py "$PROJECT_DIR" > "$PROJECT_DIR/.claude/.agent1-env.jsonl" &
    PID1=$!

    # Agent 2: Configuration Discovery
    python3 agent_config_discovery.py "$PROJECT_DIR" > "$PROJECT_DIR/.claude/.agent2-config.jsonl" &
    PID2=$!

    # Agent 3: Integration Points
    python3 agent_integration_points.py "$PROJECT_DIR" > "$PROJECT_DIR/.claude/.agent3-integration.jsonl" &
    PID3=$!

    # Wait for all agents with timeout
    timeout 15 wait $PID1 $PID2 $PID3
    AGENT_EXIT=$?
)

# Aggregate all findings
python3 aggregate_constraints.py \
    --scanner-output "$SCAN_FILE" \
    --agent1-output "$PROJECT_DIR/.claude/.agent1-env.jsonl" \
    --agent2-output "$PROJECT_DIR/.claude/.agent2-config.jsonl" \
    --agent3-output "$PROJECT_DIR/.claude/.agent3-integration.jsonl" \
    --output "$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"

# Clean up temp files
rm -f "$PROJECT_DIR/.claude/.agent*-*.jsonl"

echo "Aggregation complete: $(wc -l < "$SCAN_FILE") total constraints"
```

**Aggregation Logic** (`aggregate_constraints.py`):

```python
def aggregate_constraints(scanner_output, agent_outputs):
    """Merge scanner + agent findings into unified NDJSON.

    Deduplication rules:
    1. Same constraint ID → prefer highest severity
    2. Similar descriptions + same category → merge as one
    3. Conflicting recommendations → score by agent type (scanner=0.6, env=0.8, config=0.9)
    """

    # Parse all inputs
    all_constraints = {}  # constraint_id → constraint

    # Load scanner results
    with open(scanner_output) as f:
        for line in f:
            obj = json.loads(line)
            if obj.get('_type') == 'constraint':
                constraint_id = obj['id']
                all_constraints[constraint_id] = {
                    **obj,
                    'source': 'scanner',
                    'confidence': 1.0,
                }

    # Load agent results (with timeout handling)
    for agent_file in agent_outputs:
        if not agent_file.exists():
            continue
        with open(agent_file) as f:
            for line in f:
                if not line.strip():
                    continue
                obj = json.loads(line)
                constraint_id = obj.get('constraint_id')

                # Check for duplicates
                if constraint_id in all_constraints:
                    # Merge: prefer higher severity
                    existing = all_constraints[constraint_id]
                    severity_rank = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
                    if severity_rank[obj['severity']] < severity_rank[existing['severity']]:
                        all_constraints[constraint_id] = {
                            **obj,
                            'source': 'merged',
                            'merged_with': existing.get('source'),
                        }
                else:
                    # New constraint from agent
                    all_constraints[constraint_id] = {
                        **obj,
                        'source': obj.get('agent_id', 'unknown'),
                        'confidence': 0.8,  # Slightly lower than scanner
                    }

    # Output aggregated results in NDJSON
    # Preserve metadata from scanner
    yield metadata

    for constraint_id, constraint in sorted(
        all_constraints.items(),
        key=lambda x: severity_rank[x[1]['severity']]
    ):
        yield constraint

    # Include busywork from scanner (unchanged)
    for busywork in scanner_busywork:
        yield busywork
```

---

### 4. AUQ Integration Points

#### 4.1 Step 1.6.2.5: Load Aggregated Results (Enhanced)

**No changes to bash parsing logic**, but output now includes agent findings:

```bash
=== CONSTRAINT SCAN SUMMARY ===
SEVERITY_COUNTS: critical=1 high=5 medium=3 low=2 total=11
  BREAKDOWN BY SOURCE:
    scanner: 8 (hardcoded-{001..008})
    env-agent: 2 (agent-env-{001..002})
    config-agent: 1 (agent-config-001)
BUSYWORK_COUNT: 10

=== CONSTRAINTS (NDJSON) ===
{"_type":"constraint","id":"hardcoded-001","severity":"high",...,"source":"scanner"}
{"_type":"constraint","id":"agent-env-001","severity":"high",...,"source":"env-agent"}
...
```

#### 4.2 Step 1.6.3: Forbidden Items (multiSelect, Enhanced)

Claude parses NDJSON and builds options, grouping by source:

```yaml
Use AskUserQuestion:
  question: "What should Ralph avoid? (1 critical, 5 high detected)"
  header: "Forbidden"
  multiSelect: true
  options:
    # === SCANNER FINDINGS ===
    - label: "Hardcoded path: /Users/terryli/..."
      description: "(HIGH) pyproject.toml:15 [scanner] - Use environment variable"

    # === ENVIRONMENT AGENT FINDINGS ===
    - label: "Python 3.10 detected (3.11 required)"
      description: "(HIGH) runtime [env-agent] - Upgrade Python to 3.11+"
      resolution_steps:
        - "brew install python@3.11"
        - "pyenv local 3.11"

    # === CONFIGURATION AGENT FINDINGS ===
    - label: "Missing Doppler auth token"
      description: "(MEDIUM) ~/.doppler/credentials [config-agent] - Set up auth"

    # === STATIC FALLBACK CATEGORIES ===
    - label: "Documentation updates"
      description: "README, CHANGELOG, docstrings, comments"

    ... (rest of static categories)
```

**Key Enhancement**: Show `[source]` badge so user sees which constraints came from which discovery method.

---

### 5. Learned Behavior Enhancement

**Existing**: User selections stored in `ralph-acknowledged-constraints.jsonl`

**Enhancement**: Track source distribution to optimize future agent execution:

```json
// ~/.claude/ralph-agent-config.json (NEW - global settings)
{
  "enabled_agents": ["env-scanner", "config-discovery", "integration-points"],
  "timeout_seconds": 15,
  "agent_statistics": {
    "env-scanner": {
      "last_run": "2025-12-31T18:00:00Z",
      "avg_duration_seconds": 5.2,
      "constraints_found": 12,
      "user_selected": 3,
      "selection_rate": 0.25
    },
    "config-discovery": {
      "last_run": "2025-12-31T18:00:00Z",
      "avg_duration_seconds": 2.1,
      "constraints_found": 8,
      "user_selected": 1,
      "selection_rate": 0.125
    }
  },
  "optimization_mode": "adaptive"  // future: skip low-value agents
}
```

This enables future optimization: disable agents with consistent low selection rates.

---

## Implementation Roadmap

### Phase 1: Foundation (v10.0.0)
1. Define constraint protocol and NDJSON schema
2. Implement `aggregate_constraints.py` with deduplication
3. Create `Agent 1: Environment/Dependency Scanner` (highest ROI)
4. Integrate into Step 1.4.5 with error handling
5. Update Step 1.6.2.5 bash to parse aggregated results
6. Add `[source]` badge to AUQ option descriptions

### Phase 2: Additional Agents (v10.1.0)
1. Implement `Agent 2: Configuration Discovery`
2. Implement `Agent 3: Integration Points`
3. Parallel execution with timeout handling
4. Agent health monitoring (timeouts, crashes)

### Phase 3: Learning & Optimization (v10.2.0)
1. Track user selection patterns per agent
2. Store global agent statistics in `ralph-agent-config.json`
3. Implement adaptive agent selection (disable low-value agents)
4. Add telemetry to improve agent prompts

---

## Error Handling & Resilience

### Agent Timeout
If any agent exceeds 15 seconds:
```
Ralph timeout: env-scanner exceeded 15s, skipping
→ Constraints already found by scanner still available
→ AUQ flow continues normally
```

### Agent Crash
If an agent raises an exception:
```
Ralph error: config-discovery crashed (JSON parse error)
→ Stack trace logged to .claude/ralph-agent-errors.log
→ Constraint results so far are preserved
→ AUQ flow continues with available findings
```

### Duplicate Detection Failure
If `constraint_id` collision occurs between agents:
```
Merge strategy: Prefer scanner (confidence 1.0) over agent (confidence 0.8)
→ Both sources recorded in `merged_with` field for audit
→ User sees merged constraint with combined recommendations
```

### Network/Auth Issues (Integration Agent)
If Doppler/GitHub checks fail:
```
Constraint recorded as MEDIUM severity with retry instructions
→ Not a blocker (unlike CRITICAL scanner findings)
→ User can choose to forbid or continue
```

---

## Benefits

### For Users
1. **Richer Constraint Discovery**: Agents catch runtime/dependency issues scanner misses
2. **Actionable Recommendations**: `resolution_steps` reduce cognitive load
3. **Better Upfront Decisions**: More informed forbidden/encouraged selections
4. **Source Transparency**: `[source]` badges show where constraints come from

### For Ralph
1. **Proactive Prevention**: Catch dependency conflicts before loop starts
2. **Reduced Failure Rate**: Agent discoveries prevent mid-loop crashes
3. **Learning Opportunity**: Track which constraints users care about
4. **Future Optimization**: Disable agents with <20% selection rate

---

## Non-Scope (Future)

1. **Agent-Generated Fixes**: Agents only discover, don't propose code changes
2. **Interactive Remediation**: No inline agent-guided fixes during AUQ
3. **Persistent Agent Memory**: Agents are stateless (future: semantic cache)
4. **Custom Agent Registration**: Only 3 built-in agents (can extend later)

---

## Data Flow Example

### Concrete Scenario

```
$ /ralph:start --production

# Step 1.4 Output:
Running constraint-scanner...
  Found 8 constraints (3 HIGH)

Spawning Explore agents...
  env-scanner: Found 2 constraints (2 HIGH)
  config-discovery: Found 1 constraint (1 MEDIUM)
  integration-points: Timeout after 12s (2 MEDIUM skipped)

Aggregation complete: 11 total constraints
  Source distribution: scanner=8 agents=3 timeout=1

# Step 1.6.3 AUQ Output:
"What should Ralph avoid? (3 critical, 5 high detected)"

Options shown to user:
  [x] Hardcoded path: /Users/terryli/eon (HIGH) [scanner]
  [x] Python 3.10 detected (HIGH) [env-agent]
  [x] uv.lock out of date (MEDIUM) [env-agent]
  [ ] Missing Doppler token (MEDIUM) [config-agent]
  [ ] Documentation updates
  [ ] Dependency upgrades
  ...

User selections saved with agent source tracking.
```

---

## Configuration Example

**In `.claude/ralph-config.json`** (after Agent phase integration):

```json
{
  "version": "3.2.0",
  "state": "running",

  "constraint_discovery": {
    "enabled_agents": ["env-scanner", "config-discovery", "integration-points"],
    "timeout_seconds": 15,
    "skip_timeout_agents": false,
    "aggregate_similar": true,
    "min_confidence_threshold": 0.6
  },

  "constraint_scan": {
    "scan_timestamp": "2025-12-31T18:00:00Z",
    "total_constraints": 11,
    "by_source": {
      "scanner": 8,
      "env-agent": 2,
      "config-agent": 1
    }
  },

  "guidance": {
    "forbidden": ["Hardcoded path: /Users/terryli/eon", "Python 3.10"],
    "encouraged": ["Performance improvements"],
    "timestamp": "2025-12-31T18:15:00Z"
  }
}
```

---

## References

- Existing: [ADR: Ralph Constraint Scanning](/docs/adr/2025-12-29-ralph-constraint-scanning.md)
- Config Schema: `/plugins/ralph/hooks/core/config_schema.py`
- Start Command: `/plugins/ralph/commands/start.md` (Steps 1.4.5, 1.6.2.5, 1.6.3)
- Discovery Module: `/plugins/ralph/hooks/ralph_discovery.py`

