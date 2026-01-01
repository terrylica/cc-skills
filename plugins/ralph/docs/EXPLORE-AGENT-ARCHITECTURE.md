# Explore Agent Integration: Architecture Diagrams

## 1. Discovery Phase Data Flow

```
Ralph /start Command
        │
        ├─────────────────────────────────────────────┐
        │                                             │
        v                                             v
┌───────────────────────┐               ┌────────────────────────────┐
│  Constraint Scanner   │               │  Explore Agents (Parallel) │
│  (Static Analysis)    │               │                            │
│                       │               ├────────────────────────────┤
│ • Hardcoded paths     │               │ Agent 1: Environment       │
│ • Rigid structure     │               │ • Python version           │
│ • Global hooks        │               │ • uv.lock state           │
│                       │               │ • Missing deps            │
│ Runtime: ~2s          │               │ Runtime: ~5s              │
└───────┬───────────────┘               │                            │
        │                               │ Agent 2: Configuration     │
        │                               │ • .claude/settings.json    │
        │                               │ • .claude/ralph-config     │
        │                               │ • mise.toml validation     │
        │                               │ Runtime: ~2s              │
        │                               │                            │
        │                               │ Agent 3: Integration       │
        │                               │ • GitHub auth             │
        │                               │ • Doppler/1Password       │
        │                               │ • SSH keys                │
        │                               │ • Network checks          │
        │                               │ Runtime: ~5s              │
        │                               │ (timeout: 15s)            │
        │                               └────────┬───────────────────┘
        │                                        │
        └─────────────────────┬───────────────────┘
                              │
                    ┌─────────v──────────┐
                    │  Aggregation       │
                    │  (Deduplication    │
                    │   & Merge)         │
                    └─────────┬──────────┘
                              │
                    ┌─────────v──────────────┐
                    │  Unified NDJSON       │
                    │  (All Constraints)    │
                    │  with metadata:       │
                    │  • severity           │
                    │  • source badge       │
                    │  • confidence         │
                    │  • resolution_steps   │
                    └────────────┬──────────┘
                                 │
                    ┌────────────v─────────────┐
                    │  Step 1.6.2.5            │
                    │  Load & Parse Results    │
                    │                          │
                    │ Extract metrics:         │
                    │ • Count by severity      │
                    │ • Count by source        │
                    │ • Total constraint count │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────v─────────────┐
                    │  AUQ Cascade            │
                    │  (Steps 1.6.3-1.6.6)    │
                    │                          │
                    │ • Forbidden (multiSel)  │
                    │ • Custom forbidden      │
                    │ • Encouraged (multiSel) │
                    │ • Custom encouraged     │
                    │ • Config write + save   │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────v─────────────┐
                    │  Execution Begins       │
                    │  (Step 2)               │
                    └─────────────────────────┘
```

---

## 2. Constraint Format Evolution

### Current (v9.2.0) - Scanner Only

```
NDJSON File: .claude/ralph-constraint-scan.jsonl

Line 1 (Metadata):
{"_type":"metadata","scan_timestamp":"2025-12-31T18:00:00Z",...}

Lines 2-9 (Constraints):
{"_type":"constraint","id":"hardcoded-001","severity":"high",...}
{"_type":"constraint","id":"hardcoded-002","severity":"high",...}
...

Lines 10-19 (Busywork):
{"_type":"busywork","id":"busywork-lint","name":"Linting/style",...}
...

Total: ~20 lines, all from single source (scanner)
```

### Proposed (v10.0.0+) - Scanner + Agents

```
NDJSON File: .claude/ralph-constraint-scan.jsonl (unchanged name)

Line 1 (Metadata):
{"_type":"metadata",...,"sources":["scanner","env-agent","config-agent"],...}

Lines 2-12 (Aggregated Constraints):
{"_type":"constraint","id":"hardcoded-001",...,"source":"scanner",...}
{"_type":"constraint","id":"agent-env-001",...,"source":"env-agent",...}
{"_type":"constraint","id":"agent-env-002",...,"source":"env-agent",...}
{"_type":"constraint","id":"agent-config-001",...,"source":"config-agent",...}
...

Lines 13-22 (Busywork - unchanged):
{"_type":"busywork",...}
...

Total: ~25 lines, multiple sources with deduplication
```

---

## 3. Parallel Agent Execution Model

```
/ralph:start invoked
        │
        v
┌──────────────────────────────────────────────────────────┐
│  Step 1.4.5: Parallel Discovery (timeout: 15 seconds)    │
└──────────────────────────┬───────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        v                  v                  v
   ┌────────────┐  ┌────────────┐  ┌────────────┐
   │   Agent1   │  │   Agent2   │  │   Agent3   │
   │  (Env)     │  │  (Config)  │  │ (Integ.)   │
   │            │  │            │  │            │
   │ Start: 0s  │  │ Start: 0s  │  │ Start: 0s  │
   │ Est: 5s    │  │ Est: 2s    │  │ Est: 5s    │
   │            │  │            │  │            │
   └────────┬───┘  └────────┬───┘  └────────┬───┘
            │               │               │
            │ [Timeout at 15s boundary]     │
            │               │               │
        ┌───v───────────────v───────────────v──┐
        │  Aggregation Layer                    │
        │  (Merges results, deduplicates,      │
        │   assigns confidence scores)         │
        └───────────────┬──────────────────────┘
                        │
                        v
              ┌─────────────────────┐
              │  Unified Findings   │
              │  (11 constraints)   │
              └─────────┬───────────┘
                        │
              ┌─────────v──────────┐
              │ Learned Behavior   │
              │ (.jsonl tracking)  │
              └────────────────────┘

Timing:
┌────────────────────────────────────────────┐
│ Scanner: |--------|  (2s, blocks until)    │
│ Agent 1: |--------|--------|               │ (5s, parallel)
│ Agent 2: |--------|                        │ (2s, parallel)
│ Agent 3: |--------|--------|--------|      │ (5s, parallel, or timeout)
│          0s       5s       10s      15s    │
└────────────────────────────────────────────┘
```

---

## 4. Severity Distribution Visualization

### Before (v9.2.0)

```
Constraint Severity Distribution
CRITICAL: ⬛
HIGH:     ⬛⬛⬛
MEDIUM:   ⬛⬛
LOW:      ⬛

Total: 8 constraints (scanner only)
Sources: [scanner]
```

### After (v10.0.0)

```
Constraint Severity Distribution
CRITICAL: ⬛
HIGH:     ⬛⬛⬛ + ⬜⬜  (3 scanner + 2 agent)
MEDIUM:   ⬛⬛ + ⬜    (2 scanner + 1 agent)
LOW:      ⬛

Total: 11 constraints (8 scanner + 3 agents)
Sources: [scanner, env-agent, config-agent]

Legend:
  ⬛ = from scanner
  ⬜ = from agents
```

---

## 5. AUQ Option Generation Pipeline

```
┌─────────────────────────────────────────────────────────┐
│  Step 1.6.2.5 Output: Parsed NDJSON Constraints        │
└──────────────────────┬──────────────────────────────────┘
                       │
      ┌────────────────┴────────────────┐
      │                                 │
      v                                 v
┌───────────────┐              ┌───────────────┐
│  Constraint   │              │  Busywork     │
│  Lines        │              │  Categories   │
│  (11 items)   │              │  (10 items)   │
└───────┬───────┘              └────────┬──────┘
        │                               │
        │                    ┌──────────┘
        │                    │
        v                    v
┌──────────────────────────────────────┐
│  Build AUQ Options (Step 1.6.3)      │
│                                      │
│  Section 1: Constraint-Derived       │
│  ───────────────────────────────────  │
│  ☐ Hardcoded path: /Users/terryli   │
│    (HIGH) [scanner] pyproject:15     │
│                                      │
│  ☐ Python 3.10 detected              │
│    (HIGH) [env-agent] runtime        │
│                                      │
│  ☐ uv.lock out of date               │
│    (MEDIUM) [env-agent] deps         │
│                                      │
│  ☐ Missing Doppler auth              │
│    (MEDIUM) [config-agent] auth      │
│                                      │
│  Section 2: Static Fallbacks         │
│  ───────────────────────────────────  │
│  ☐ Documentation updates             │
│  ☐ Dependency upgrades               │
│  ☐ Test coverage expansion           │
│  ... (6 more static options)          │
│                                      │
└──────────────────┬───────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        v                     v
┌──────────────────┐  ┌────────────────┐
│  User Selects    │  │  Custom Input  │
│  (multiSelect)   │  │  (Step 1.6.4)  │
│                  │  │                │
│  [x] High-1      │  │  "Refactor DB" │
│  [x] High-2      │  │  "Schema work" │
│  [ ] High-3      │  └────────────────┘
│  [x] Medium-1    │
│  [ ] Medium-2    │
│  [x] Doc updates │
│  [ ] Dependencies│
│                  │
└────────┬─────────┘
         │
         v
┌───────────────────────────────────┐
│  Collect Final Selections          │
│                                   │
│  FORBIDDEN:                        │
│  [                                │
│    "Hardcoded path: /Users/...",  │
│    "Python 3.10 detected",        │
│    "Missing Doppler auth",        │
│    "Documentation updates",       │
│    "Refactor DB",                 │
│    "Schema work"                  │
│  ]                                │
│                                   │
│  CONSTRAINT_IDS (for learn):      │
│  [                                │
│    "hardcoded-001",               │
│    "agent-env-002",               │
│    "agent-config-001"             │
│  ]                                │
└──────────┬────────────────────────┘
           │
           v
┌─────────────────────────────────────────┐
│  Step 1.6.7: Persist Configuration      │
│                                         │
│  Write to .claude/ralph-config.json:    │
│  {                                      │
│    "guidance": {                        │
│      "forbidden": [... 6 items ...],    │
│      "encouraged": [...],               │
│      "timestamp": "2025-12-31T18:15Z"   │
│    },                                   │
│    "constraint_scan": {                 │
│      "scan_timestamp": "...",           │
│      "constraints": [...all 11...],     │
│      "sources": ["scanner", "agents"]   │
│    }                                    │
│  }                                      │
│                                         │
│  Append to .jsonl (Learned Behavior):   │
│  [constraint-id: "hardcoded-001", ...]  │
│  [constraint-id: "agent-env-002", ...]  │
│  [constraint-id: "agent-config-001"...] │
└─────────────────────────────────────────┘
```

---

## 6. Error Handling State Machine

```
                          ┌─────────────────────┐
                          │  Agent Execution    │
                          │  (timeout: 15s)     │
                          └──────────┬──────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    v                v                v
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │ Agent 1      │ │ Agent 2      │ │ Agent 3      │
            │ completes    │ │ completes    │ │ timeout at   │
            │ with 2       │ │ with 1       │ │ 13s, killed  │
            │ constraints  │ │ constraint   │ │ (partial=0)  │
            └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
                   │                │                │
                   └────────────────┼────────────────┘
                                    │
                    ┌───────────────v────────────────┐
                    │  Aggregation Logic             │
                    │  (error handling path)         │
                    │                                │
                    │  Scanner:   8 ✓               │
                    │  Agent 1:   2 ✓               │
                    │  Agent 2:   1 ✓               │
                    │  Agent 3:   0 ⏱ timeout      │
                    │                                │
                    │  Result: 11 constraints        │
                    │  Degraded: 1 agent             │
                    │  Severity: MEDIUM (not crit)   │
                    │  Status: "Partial success"     │
                    └───────────────┬────────────────┘
                                    │
                    ┌───────────────v────────────────┐
                    │  User Notification             │
                    │                                │
                    │  "Ralph timeout: agent3 took   │
                    │   >15s, skipped                │
                    │   (Scanner + 2 agents OK)"     │
                    └───────────────┬────────────────┘
                                    │
                    ┌───────────────v────────────────┐
                    │  AUQ Flow Continues            │
                    │  (with 11 constraints)         │
                    └────────────────────────────────┘
```

---

## 7. Configuration Schema Evolution

### Current (v3.0.0)

```python
class RalphConfig(BaseModel):
    version: str = "3.0.0"
    state: LoopState = LoopState.STOPPED

    # Sub-configs
    loop_detection: LoopDetectionConfig
    completion: CompletionConfig
    validation: ValidationConfig
    loop_limits: LoopLimitsConfig
    # ... (more)

    # NEW v3.0.0
    guidance: GuidanceConfig
    constraint_scan: ConstraintScanConfig | None

    # NEW v3.0.0
    skip_constraint_scan: bool = False
```

### Proposed (v3.2.0+)

```python
class AgentConfig(BaseModel):
    """Configuration for Explore agents."""
    enabled: bool = True
    agent_id: str  # "env-scanner" | "config-discovery" | "integration-points"
    timeout_seconds: int = 15
    skip_on_timeout: bool = False
    selection_rate: float = 0.0  # Populated by learning phase

class ConstraintDiscoveryConfig(BaseModel):
    """Configuration for constraint discovery phase."""
    enabled_agents: list[str] = [
        "env-scanner",
        "config-discovery",
        "integration-points"
    ]
    timeout_seconds: int = 15
    skip_timeout_agents: bool = False
    aggregate_similar: bool = True
    min_confidence_threshold: float = 0.6
    agents: list[AgentConfig] = Field(default_factory=list)

class RalphConfig(BaseModel):
    version: str = "3.2.0"
    state: LoopState = LoopState.STOPPED

    # NEW v3.2.0: Agent coordination
    constraint_discovery: ConstraintDiscoveryConfig = \
        Field(default_factory=ConstraintDiscoveryConfig)

    # Existing
    loop_detection: LoopDetectionConfig
    completion: CompletionConfig
    # ... (rest unchanged)
```

---

## 8. User Experience Timeline

```
User runs: /ralph:start --production

T+0s  ┌─ "Running constraint-scanner..."
T+2s  ├─ "Spawning Explore agents..."
T+2s  ├─ "Agent 1: Environment Scanner..."
T+2s  ├─ "Agent 2: Configuration Discovery..."
T+2s  ├─ "Agent 3: Integration Points..."
      │
T+5s  ├─ "Agent 2 complete: 1 constraint found"
      │
T+7s  ├─ "Agent 1 complete: 2 constraints found"
      │
T+13s ├─ "Agent 3 timeout: skipping (12s elapsed)"
      │
T+13s ├─ "Aggregation complete: 11 total constraints"
      ├─ "  Scanner: 8 | Agents: 3 | Deduped: 0"
      │
T+14s ├─ AskUserQuestion: "What should Ralph avoid?"
      │  (Shows 4 constraint-derived options + 10 static)
      │
T+30s ├─ User selects: 4 constraints + 2 static + custom items
      │
T+31s ├─ AskUserQuestion: "Add custom forbidden?"
T+35s ├─ User input: "Refactor DB, Schema changes"
      │
T+36s ├─ AskUserQuestion: "What should Ralph prioritize?"
T+40s ├─ User selects: 2 categories
      │
T+41s ├─ AskUserQuestion: "Add custom encouraged?"
T+45s ├─ User input: "Feature engineering"
      │
T+46s ├─ "Saving configuration..."
T+47s ├─ "✓ Guidance saved"
T+47s ├─ "✓ Learned behavior saved (3 constraints acknowledged)"
      │
T+48s └─ "Ralph Loop: PRODUCTION MODE"
        "State: RUNNING"
        "Config: .claude/ralph-config.json"
        "Ready for OODA cycle..."
```

---

## 9. Deduplication Matrix

```
┌─────────────────────────────────────────────────────────┐
│  Agent Findings Deduplication Logic                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Scenario 1: Exact ID Match                            │
│  ────────────────────────────                          │
│  hardcoded-001 from scanner (severity: HIGH)           │
│  hardcoded-001 from config-agent (severity: CRITICAL)  │
│                                                         │
│  Action: MERGE                                          │
│  Result: hardcoded-001 (severity: CRITICAL)            │
│          merged_with: "scanner,config-agent"           │
│          resolution_steps: [combined steps]            │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Scenario 2: Semantic Similarity (category match)      │
│  ────────────────────────────────────────────────────   │
│  hardcoded-001: "Path /Users/terryli in config.toml"   │
│  agent-env-001: "Hardcoded home dir path detected"     │
│  Category: both "hardcoded_path"                       │
│                                                         │
│  Action: KEEP SEPARATE (different files)               │
│  Reason: Overlap is normal, both are valid             │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Scenario 3: Conflicting Recommendations               │
│  ────────────────────────────────────────────────────   │
│  hardcoded-002: "Use environment variable"             │
│  agent-config-001: "Hardcode /opt/data as default"     │
│  (Conflicting recommendations)                         │
│                                                         │
│  Action: KEEP SEPARATE                                 │
│  Reason: Recommend scanner (confidence 1.0) over agent │
│          Note conflict in resolution_steps             │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Scoring: severity_rank[constraint['severity']]        │
│           critical=0, high=1, medium=2, low=3          │
│           Lower rank = higher priority                 │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 10. Integration with Ralph Loop State Machine

```
                    ┌────────────────────┐
                    │   /ralph:start      │
                    │   invoked           │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ Step 1.4            │
                    │ Constraint          │
                    │ Discovery           │
                    │ (Static + Agents)   │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ Step 1.5            │
                    │ Preset              │
                    │ Confirmation        │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ Step 1.6            │
                    │ Session Guidance    │
                    │ (AUQ Cascade)       │
                    │ Forbidden/Encour    │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────────────┐
                    │ Step 2: Loop Execution      │
                    │ (RUNNING state)             │
                    │                             │
                    │ • PreToolUse: Check rules   │
                    │ • Execute iteration         │
                    │ • Check constraints         │
                    │ • PostToolUse: Validate     │
                    │                             │
                    │ Loop-until-done.py         │
                    └──────────┬──────────────────┘
                               │
                    ┌──────────v──────────┐
                    │ Step 3: OODA        │
                    │ (Alpha Forge only)  │
                    │                     │
                    │ • OBSERVE metrics   │
                    │ • ORIENT strategy   │
                    │ • DECIDE next       │
                    │ • ACT /research     │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ Stop Condition      │
                    │ met?                │
                    │                     │
                    │ • Completion marker │
                    │ • Time limits       │
                    │ • Iterations        │
                    │ • Loop detected     │
                    │ • /ralph:stop       │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ State: DRAINING     │
                    │ (grace period)      │
                    └──────────┬──────────┘
                               │
                    ┌──────────v──────────┐
                    │ State: STOPPED      │
                    │ Loop Complete       │
                    └────────────────────┘

Constraint discovery occurs once at start (Step 1.4)
→ Provides context for entire session
→ User selections persist in config
→ Learned behavior updates acknowledgment file
```

