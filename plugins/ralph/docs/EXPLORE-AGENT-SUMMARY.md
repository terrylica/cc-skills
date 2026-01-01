# Explore Agent Integration: Executive Summary

## Overview

This design integrates **Claude Code's Explore agents** (autonomous discovery capability) into Ralph's `/ralph:start` preflight flow to enhance constraint discovery. Instead of relying solely on static file analysis, Ralph will spawn 3 parallel agents to discover runtime dependencies, configuration issues, and integration requirements.

**Key Outcome**: Users get better-informed forbidden/encouraged selections by seeing constraints from multiple discovery methods.

---

## What's the Problem?

### Current State (v9.2.0)

```
/ralph:start
    ↓
constraint-scanner.py (static analysis)
    ├─ Hardcoded paths
    ├─ Rigid structures
    ├─ Global hooks
    └─ [Done in 2 seconds]
    ↓
AUQ: Forbidden/Encouraged questions
```

**Limitation**: Static analysis misses runtime constraints:
- Python version mismatches (detected at runtime)
- Dependency conflicts in uv.lock
- Missing authentication tokens
- Configuration file states

---

## What's the Solution?

### Proposed Enhancement (v10.0.0+)

```
/ralph:start
    ↓
[Parallel Discovery]
├─ constraint-scanner.py (2s, static)
└─ Explore Agents (parallel, 15s total)
   ├─ Agent 1: Environment Scanner (Python, uv, deps)
   ├─ Agent 2: Configuration Discovery (.claude, mise.toml)
   └─ Agent 3: Integration Points (auth, networking)
    ↓
Aggregation (dedup, merge, confidence scores)
    ↓
Unified NDJSON (11 constraints instead of 8)
    ↓
AUQ: Rich Forbidden/Encouraged with [source] badges
```

**Key Benefits**:
1. **Richer Discovery**: 3 agents find what scanner misses
2. **Source Transparency**: Show users which method found each constraint
3. **Actionable Recommendations**: Multi-step resolution guides
4. **Learned Behavior**: Track which constraints users care about

---

## Core Design Decisions

### 1. Augment, Don't Replace

**Decision**: Agents work alongside scanner, not instead of it.

- Scanner: Fast, deterministic, 100% confident
- Agents: Slower, but context-aware
- Aggregator: Merges findings with deduplication

### 2. Parallel Execution with Timeout

**Decision**: All 3 agents run simultaneously, killed at 15s boundary.

```
T+0s  └─ Scanner starts (blocking)
T+0s  └─ Agents 1,2,3 start (parallel)
T+5s  └─ Agent 2 done (2s)
T+7s  └─ Agent 1 done (5s)
T+13s └─ Agent 3 done (5s) OR timeout at T+15s
       └─ Continue with what we have (no single point of failure)
```

### 3. Canonical Constraint Format

**Decision**: All constraints (scanner + agents) use same schema with `source` badge.

```json
{
    "constraint_id": "agent-env-001",
    "severity": "high",
    "category": "python_version",
    "description": "Python 3.10 detected (3.11 required)",
    "source": "env-scanner",  // <-- Badge for AUQ display
    "recommendation": "Upgrade Python: brew install python@3.11",
    "resolution_steps": [...]
}
```

### 4. Learned Behavior (Future Growth)

**Decision**: Track selection patterns globally for v10.2.0 optimization.

```json
// ~/.claude/ralph-agent-config.json (NEW)
{
    "agent_statistics": {
        "env-scanner": {
            "total_runs": 5,
            "constraints_found": 12,
            "user_selected": 3,
            "selection_rate": 0.25  // 25% of findings selected
        }
        // If selection_rate < 10% in v10.2.0, disable agent
    }
}
```

---

## Integration Points

### Step 1.4.5 (NEW): Parallel Discovery

**In `/ralph:start` command**:

```bash
# Run scanner (blocking, ~2s)
uv run constraint-scanner.py ...

# Spawn agents in parallel (timeout after 15s)
/usr/bin/env bash << 'AGENTS'
  # Agent 1, 2, 3 all run simultaneously
  python3 agent_env_scanner.py & PID1=$!
  python3 agent_config_discovery.py & PID2=$!
  python3 agent_integration_points.py & PID3=$!
  timeout 15 wait $PID1 $PID2 $PID3
AGENTS

# Aggregate all findings
python3 aggregate_constraints.py \
  --scanner-output ... \
  --agent1-output ... \
  --agent2-output ... \
  --agent3-output ... \
  --output .claude/ralph-constraint-scan.jsonl
```

### Step 1.6.2.5 (Enhanced): Load Aggregated Results

**No parsing changes**, but output now includes agent findings:

```
=== CONSTRAINT SCAN SUMMARY ===
SEVERITY_COUNTS: critical=1 high=5 medium=3 low=2 total=11
  BY SOURCE: scanner=8 env-agent=2 config-agent=1

=== CONSTRAINTS (NDJSON) ===
{"id":"hardcoded-001",...,"source":"scanner"}
{"id":"agent-env-001",...,"source":"env-agent"}
...
```

### Step 1.6.3 (Enhanced): Forbidden Items (multiSelect)

**AUQ now shows source badge for each constraint**:

```yaml
Use AskUserQuestion:
  question: "What should Ralph avoid? (1 critical, 5 high detected)"
  multiSelect: true
  options:
    - label: "Hardcoded path: /Users/terryli"
      description: "(HIGH) pyproject.toml:15 [scanner] - Use env var"
    - label: "Python 3.10 detected"
      description: "(HIGH) runtime [env-agent] - Upgrade to 3.11"
    - label: "uv.lock out of date"
      description: "(MEDIUM) uv.lock [env-agent] - Regenerate lock"
    ...
```

### Step 1.6.7 (Enhanced): Persist with Learned Behavior

**Write config AND track agent contributions**:

```bash
# Write .claude/ralph-config.json with constraint_scan metadata
jq '.guidance = {...}' ...

# Append to .jsonl for learning
echo '{"id":"agent-env-001",...}' >> .claude/ralph-acknowledged-constraints.jsonl
```

---

## Three Agents Specification

### Agent 1: Environment Scanner (5s avg)

**Purpose**: Check Python runtime, dependencies, virtual environment

**Constraints Discovered**:
- Python version mismatch (`requires-python` in pyproject.toml)
- `uv.lock` out of date with `pyproject.toml`
- Missing optional dependencies (pydantic, filelock)
- Virtual environment state issues

**Output Format**: NDJSON, each line is one constraint

**Example**:
```json
{"agent_id":"env-scanner","constraint_id":"agent-env-001","severity":"high","description":"Python 3.10 detected (3.11 required)","resolution_steps":["python3 --version","brew install python@3.11"]}
```

### Agent 2: Configuration Discovery (2s avg)

**Purpose**: Scan all config files for incompatibilities

**Constraints Discovered**:
- Missing `.claude/ralph-config.json` (first run)
- Conflicting hooks in `~/.claude/settings.json`
- Invalid `mise.toml` syntax
- Environment variable pollution
- Feature flags conflicts

**Output Format**: Same NDJSON format

**Example**:
```json
{"agent_id":"config-discovery","constraint_id":"agent-config-001","severity":"medium","description":"Missing Ralph config (first run)","recommendation":"Will be created during setup"}
```

### Agent 3: Integration Points (5s avg, or timeout)

**Purpose**: Detect authentication and external dependencies

**Constraints Discovered**:
- Missing GitHub token (for `git` operations)
- Unconfigured Doppler/1Password secrets
- Missing SSH keys
- Network connectivity issues
- Tools missing from PATH (git, jq, fd, rg)

**Output Format**: Same NDJSON format

**Example**:
```json
{"agent_id":"integration-points","constraint_id":"agent-integ-001","severity":"medium","description":"GitHub token not configured","recommendation":"Run: gh auth login"}
```

---

## Aggregation Algorithm

### Deduplication Rules

1. **Exact ID Match**: Same `constraint_id` → prefer highest severity
   ```
   hardcoded-001 (scanner, HIGH) + hardcoded-001 (agent, CRITICAL)
   → merged: hardcoded-001 (CRITICAL), merged_with: ["scanner"]
   ```

2. **Semantic Similarity**: Same category + file → keep separate (valid overlap)
   ```
   hardcoded-001: /Users/terryli in pyproject.toml
   agent-env-001: Hardcoded home dir detected
   → both kept (different files, both valid)
   ```

3. **Conflicting Recommendations**: Keep separate with confidence scores
   ```
   scanner (confidence 1.0) preferred over agent (confidence 0.8)
   ```

### Sorting

After dedup, sort by severity (critical → high → medium → low), then by ID.

---

## Error Handling & Resilience

### Agent Timeouts
- If any agent exceeds 15s: Killed gracefully, no error
- Other agents continue
- Results aggregated with available constraints
- User informed: "Agent 3 timeout: skipping (Scanner + 2 agents OK)"

### Agent Crashes
- Stack trace logged to `.claude/ralph-agent-errors.log`
- Partial results preserved
- AUQ continues with available findings

### Duplicate Detection Failure
- Both sources recorded in `merged_with` field
- User sees combined findings + recommendations
- Audit trail preserved

### Network Issues (Integration Agent)
- Constraint recorded as MEDIUM, not blocker
- User can choose to forbid or continue

---

## User Experience Timeline

```
T+0s  $ /ralph:start --production
T+2s  Running constraint-scanner...
      Running Explore agents...
T+5s  Agent 2 complete: 1 constraint
T+7s  Agent 1 complete: 2 constraints
T+15s Agent 3 timeout: skipped
      Aggregation complete: 11 constraints

T+20s [AUQ] "What should Ralph avoid? (1 critical, 5 high detected)"
      Shows 4 constraint-derived options with [source] badges
      Shows 10 static categories
T+30s [AUQ] "Add custom forbidden items? (comma-separated)"
T+40s [AUQ] "What should Ralph prioritize?"
T+45s [AUQ] "Add custom encouraged items?"
T+47s ✓ Guidance saved
      ✓ Learned behavior saved (3 constraints acknowledged)
```

---

## Implementation Roadmap

### Phase 1 (v10.0.0): Foundation
1. Define constraint protocol + NDJSON schema
2. Implement `aggregate_constraints.py`
3. Implement Agent 1 (Environment Scanner)
4. Integrate into Step 1.4.5 with timeouts
5. Update Step 1.6.2.5 bash parsing
6. Add `[source]` badges to AUQ options

### Phase 2 (v10.1.0): Additional Agents
1. Implement Agent 2 (Configuration Discovery)
2. Implement Agent 3 (Integration Points)
3. Parallel execution with proper error handling
4. Agent health monitoring

### Phase 3 (v10.2.0): Learning & Optimization
1. Track selection patterns per agent
2. Store global statistics in `ralph-agent-config.json`
3. Auto-disable low-value agents (selection_rate < 10%)
4. Telemetry to improve agent prompts

---

## Files to Create/Modify

### New Files
- `/plugins/ralph/docs/EXPLORE-AGENT-INTEGRATION-DESIGN.md` (design spec)
- `/plugins/ralph/docs/EXPLORE-AGENT-ARCHITECTURE.md` (diagrams)
- `/plugins/ralph/docs/EXPLORE-AGENT-IMPLEMENTATION.md` (reference)
- `/plugins/ralph/scripts/agent_env_scanner.py` (Agent 1)
- `/plugins/ralph/scripts/agent_config_discovery.py` (Agent 2)
- `/plugins/ralph/scripts/agent_integration_points.py` (Agent 3)
- `/plugins/ralph/scripts/aggregate_constraints.py` (aggregator)

### Modified Files
- `/plugins/ralph/commands/start.md` (add Step 1.4.5, enhance 1.6.2.5)
- `/plugins/ralph/hooks/core/config_schema.py` (add v3.2.0 models)
- `/plugins/ralph/README.md` (document agent discovery)

---

## Non-Scope (Future)

1. Agent-generated fixes (only discover, not fix)
2. Interactive remediation (inline agent guidance)
3. Persistent agent memory (stateless execution)
4. Custom agent registration (3 built-in agents only)

---

## Benefits Summary

### For Users
✓ Better constraint discovery (static + runtime + config + auth)
✓ Source transparency (`[source]` badges)
✓ Actionable multi-step resolution guides
✓ No slowdown (parallel execution, 15s timeout)

### For Ralph
✓ Proactive problem prevention
✓ Reduced mid-loop failures
✓ Learning foundation for future optimization
✓ Higher success rate across projects

### For cc-skills Ecosystem
✓ Demonstrates multi-agent orchestration
✓ Pattern for future agent integrations
✓ Showcase Claude Code's autonomous capabilities

---

## Questions & Answers

### Q: Why parallel execution? Why not sequential?
**A**: Parallel reduces total time from 12s (sequential) to 7s (parallel, no timeout). Users wait less, agents run simultaneously.

### Q: What if an agent times out?
**A**: Other agents continue, results are aggregated. Not a blocker. User informed of timeout, loop continues normally.

### Q: How does learning work?
**A**: Global statistics tracked in `~/.claude/ralph-agent-config.json`. In v10.2.0, agents with <10% selection rate are auto-disabled (data-driven optimization).

### Q: Can users disable specific agents?
**A**: In v3.2.0 config, yes: `constraint_discovery.enabled_agents = ["env-scanner"]` (omit unwanted agents).

### Q: How many constraints is "normal"?
**A**: Typical discovery: 8-15 constraints across all sources. Scanner alone: 5-8. Agents add 2-5 more.

### Q: What about false positives from agents?
**A**: Users select which constraints to forbid. Agents with high false-positive rate show low selection rates → disabled in v10.2.0.

---

## Architecture Diagram Quick Reference

```
Input                 Processing           Output
─────────────────────────────────────────────────────────

Scanner (2s)  ┐
Agent 1 (5s)  ├─ [Parallel/Timeout]  ─→  Aggregator  ─→  Unified NDJSON
Agent 2 (2s)  │  (15s boundary)                            (11 constraints)
Agent 3 (5s)  ┘

                                                          ↓

                                               Parse & Count
                                               ├─ severity
                                               ├─ sources
                                               └─ total

                                                          ↓

                                               AUQ Question
                                               ├─ Constraint-derived
                                               ├─ Static categories
                                               └─ [source] badges
```

---

## Related Documents

- **Design Spec**: `/plugins/ralph/docs/EXPLORE-AGENT-INTEGRATION-DESIGN.md`
- **Architecture**: `/plugins/ralph/docs/EXPLORE-AGENT-ARCHITECTURE.md`
- **Implementation**: `/plugins/ralph/docs/EXPLORE-AGENT-IMPLEMENTATION.md`
- **Current Constraint Scanner**: `/plugins/ralph/scripts/constraint-scanner.py`
- **Start Command**: `/plugins/ralph/commands/start.md`
- **Config Schema**: `/plugins/ralph/hooks/core/config_schema.py`

