# Explore Agent Integration: Complete Design Index

## Overview

This directory contains the complete specification for integrating Claude Code **Explore agents** into Ralph's `/ralph:start` constraint discovery flow. The design enables richer, multi-source constraint discovery through parallel autonomous agents.

**Status**: Proposal / Design Phase (Ready for Implementation Review)
**Version**: 1.0
**Date**: 2025-12-31

---

## Core Documents

### 1. Executive Summary ⭐
**File**: `/EXPLORE-AGENT-SUMMARY.md`

Start here if you're new. Covers:
- Problem statement (why agents?)
- Solution overview (augment scanner with agents)
- Core design decisions
- 3-agent specifications
- Implementation roadmap
- User experience timeline

**Read time**: 10 minutes
**Audience**: PMs, reviewers, stakeholders

---

### 2. Design Specification (Main Reference)
**File**: `/EXPLORE-AGENT-INTEGRATION-DESIGN.md`

The authoritative design document. Includes:
- Current constraint-scanner pipeline analysis
- Proposed enhancement architecture
- Agent protocol (canonical constraint JSON)
- Aggregation algorithm with deduplication
- AUQ integration points (Steps 1.4.5, 1.6.2.5, 1.6.3, 1.6.7)
- Learned behavior tracking for v10.2.0
- Error handling & resilience
- Benefits for users/Ralph/ecosystem
- Non-scope items

**Read time**: 25 minutes
**Audience**: Architects, implementers, reviewers

**Key Sections**:
- Section 2: Current State Analysis
- Section 3: Proposed Enhancement
- Section 4: Agent Specifications (detailed)
- Section 5: Aggregation Algorithm
- Section 8: Error Handling
- Section 9: Implementation Roadmap

---

### 3. Architecture & Data Flow (Visual)
**File**: `/EXPLORE-AGENT-ARCHITECTURE.md`

Visual diagrams and flowcharts:
1. **Discovery Phase Data Flow**: Scanner + agents → aggregator → AUQ
2. **Constraint Format Evolution**: v9.2.0 vs v10.0.0+ NDJSON
3. **Parallel Agent Execution Model**: Timeline with 15s timeout
4. **Severity Distribution**: Before/after visualization
5. **AUQ Option Generation Pipeline**: Constraint → user selection
6. **Error Handling State Machine**: Timeout/crash recovery
7. **Configuration Schema Evolution**: Pydantic v3.0.0 → v3.2.0
8. **User Experience Timeline**: T+0s to T+47s walkthrough
9. **Deduplication Matrix**: Merge rules with examples
10. **Ralph Loop State Machine**: Integration with OODA cycle

**Read time**: 15 minutes
**Audience**: Visual learners, architects, reviewers

**Key Diagrams**:
- Flow diagram (Section 1): End-to-end data flow
- Parallel execution (Section 3): Timing and timeout boundaries
- AUQ builder (Section 5): Constraint → option transformation
- Error states (Section 6): Graceful failure paths

---

### 4. Implementation Reference
**File**: `/EXPLORE-AGENT-IMPLEMENTATION.md`

Concrete code templates and examples:
1. **Agent Output Format Specification**: NDJSON schema with Python dataclass
2. **Example Outputs**: Real constraint examples from all 3 agents
3. **Aggregation Algorithm**: Full Python implementation with deduplication
4. **Agent 1 (Environment Scanner)**: Pseudo-code template
5. **Agent 2 (Configuration Discovery)**: Pseudo-code template
6. **Agent 3 (Integration Points)**: Pseudo-code template (referenced)
7. **Bash Integration**: Updated start.md Step 1.4.5
8. **Configuration Updates**: New Pydantic models for v3.2.0
9. **Global Agent Statistics**: Tracking format for learning
10. **AUQ Option Builder**: Python helper to generate AUQ options
11. **Complete Example Flow**: Full user journey output

**Read time**: 30 minutes
**Audience**: Implementers, code reviewers

**Key Code Sections**:
- Section 1: NDJSON protocol (copy-paste ready)
- Section 2: `aggregate_constraints.py` (production-ready)
- Section 3: Agent 1 template (scaffolding)
- Section 4: Bash script (Step 1.4.5 integration)
- Section 5: Pydantic models (Schema v3.2.0)

---

## Quick Navigation

### By Role

**Project Manager / Stakeholder**
→ Start with `/EXPLORE-AGENT-SUMMARY.md`

**Architect / Tech Lead**
→ Read 1) Summary 2) Design Spec 3) Architecture

**Implementer / Developer**
→ Read 1) Summary 2) Implementation Reference 3) Design Spec (as needed)

**Code Reviewer**
→ Read 1) Design Spec 2) Implementation Reference 3) Architecture (validate alignment)

**QA / Tester**
→ Read 1) Summary 2) Architecture (Section 8) 3) Implementation (Section 11)

### By Topic

**Understanding the Problem**
- Summary, Section 1-2
- Design Spec, Section 1-2

**Agent Architecture**
- Design Spec, Sections 3-4
- Architecture, Sections 1, 3, 5, 9

**Constraint Protocol**
- Design Spec, Section 4.1
- Implementation, Section 1

**Aggregation Logic**
- Design Spec, Section 5
- Implementation, Section 2
- Architecture, Section 9 (dedup matrix)

**AUQ Integration**
- Design Spec, Sections 4.2-4.3
- Architecture, Section 5
- Implementation, Section 7, 10

**Error Handling**
- Design Spec, Section 8
- Architecture, Section 6

**Configuration**
- Design Spec, Section 8 (learned behavior)
- Implementation, Section 5, 6

**Roadmap**
- Summary, Section "Implementation Roadmap"
- Design Spec, Section "Implementation Roadmap"

---

## Document Cross-References

### Summary ↔ Design Spec
- Summary Section 3 (Design Decisions) → Design Spec Sections 3-5
- Summary Section 4 (Three Agents) → Design Spec Section 4
- Summary Section 5 (Integration Points) → Design Spec Sections 4.2-4.3
- Summary Section 7 (Error Handling) → Design Spec Section 8

### Summary ↔ Architecture
- Summary Section 6 (Timeline) → Architecture Section 8
- Summary Section 3 (Key Decisions) → Architecture Sections 2, 3
- Summary Section 4 (Agents) → Architecture Sections 1, 3

### Design Spec ↔ Implementation
- Design Spec Section 4 (Agent Protocol) → Implementation Section 1
- Design Spec Section 5 (Aggregation) → Implementation Section 2
- Design Spec Section 4.2-4.3 (AUQ) → Implementation Section 7, 10

### Architecture ↔ Implementation
- Architecture Section 2 (Format Evolution) → Implementation Section 1
- Architecture Section 5 (AUQ Pipeline) → Implementation Section 10
- Architecture Section 6 (Error States) → Implementation Section 2 (error handling)

---

## Key Design Decisions (Quick Reference)

| Decision | Rationale | Impact |
|----------|-----------|--------|
| **Augment, don't replace** | Scanner is fast and confident; agents provide context | Both sources work together in aggregation |
| **Parallel execution** | Reduces total time from 12s (seq) to 7s (parallel) | Better UX, agents run simultaneously |
| **15s timeout** | Balance discovery thoroughness with user wait time | Graceful timeout, never a blocker |
| **Canonical JSON format** | All constraints use same schema with `source` badge | Unified AUQ presentation |
| **Deduplication by ID** | Prevent duplicate options in AUQ | Users see each unique constraint once |
| **Learned behavior tracking** | Foundation for v10.2.0 optimization | Data-driven agent selection |
| **Source transparency** | Users see `[scanner]` / `[env-agent]` / `[config-agent]` badges | Trust in constraint origins |

---

## Implementation Checklist

### Phase 1: Foundation (v10.0.0)
- [ ] Define constraint protocol (NDJSON schema)
- [ ] Implement `aggregate_constraints.py`
- [ ] Create `agent_env_scanner.py` (Agent 1)
- [ ] Add bash integration to start.md Step 1.4.5
- [ ] Update Step 1.6.2.5 to parse aggregated results
- [ ] Add `[source]` badge to AUQ option descriptions
- [ ] Test end-to-end with sample project
- [ ] Update `config_schema.py` with v3.0.0+ models (if not already done)

### Phase 2: Additional Agents (v10.1.0)
- [ ] Create `agent_config_discovery.py` (Agent 2)
- [ ] Create `agent_integration_points.py` (Agent 3)
- [ ] Implement timeout handling for all 3 agents
- [ ] Add health monitoring and error logging
- [ ] Test timeout scenarios
- [ ] Test crash recovery

### Phase 3: Learning & Optimization (v10.2.0)
- [ ] Implement global stats tracking (`ralph-agent-config.json`)
- [ ] Calculate selection rates per agent
- [ ] Implement auto-disable for low-value agents (<10%)
- [ ] Add telemetry dashboard (optional)

---

## Files Modified / Created

### New Files (to create)
```
/plugins/ralph/scripts/
  - agent_env_scanner.py         (Phase 1)
  - agent_config_discovery.py    (Phase 2)
  - agent_integration_points.py  (Phase 2)
  - aggregate_constraints.py     (Phase 1)
```

### Modified Files
```
/plugins/ralph/commands/
  - start.md                     (Phase 1: add Step 1.4.5, enhance 1.6.2.5)

/plugins/ralph/hooks/core/
  - config_schema.py             (Phase 1: add ConstraintDiscoveryConfig v3.2.0)

/plugins/ralph/docs/
  - (This index)
```

---

## Examples & Scenarios

### Scenario 1: Normal Execution (Agent 1 + 2 + 3 complete)
```
$ /ralph:start --production
Running constraint-scanner...         [2s]
Spawning Explore agents...
  Agent 1: Environment...            [5s]
  Agent 2: Configuration...          [2s]
  Agent 3: Integration...            [5s]
Aggregation complete: 11 constraints

[AUQ shows 4 constraint-derived options + 10 static]
```

### Scenario 2: Agent 3 Timeout (Agent 1 + 2 complete, Agent 3 killed at 15s)
```
Running constraint-scanner...         [2s]
Spawning Explore agents...
  Agent 1: Environment...            [5s]
  Agent 2: Configuration...          [2s]
  Agent 3 timeout (killed)           [15s boundary]
Aggregation complete: 10 constraints

[AUQ shows 3 constraint-derived options + 10 static]
User sees: "Agent 3 timeout: skipped (Scanner + 2 agents OK)"
```

### Scenario 3: Agent Crash (Agent 2 crashes, Agents 1 + 3 complete)
```
Running constraint-scanner...         [2s]
Spawning Explore agents...
  Agent 1: Environment...            [5s]
  Agent 2 ERROR: JSON parse failed
  Agent 3: Integration...            [5s]
Aggregation complete: 10 constraints (partial)

[AUQ shows 3 constraint-derived options + 10 static]
User sees: "Agent 2 failed: see .claude/ralph-agent-errors.log"
```

---

## Testing Strategy

### Unit Tests (Phase 1)
- Test aggregation algorithm with sample constraints
- Test deduplication logic (exact ID match, merge rules)
- Test severity ranking and sorting
- Test NDJSON parsing/generation

### Integration Tests (Phase 2)
- Test Agent 1 with Python 3.9/3.10/3.11/3.12
- Test Agent 2 with missing/corrupted configs
- Test Agent 3 with network disabled
- Test parallel execution with timeouts
- Test learned behavior tracking

### End-to-End Tests (Phase 1+)
- Run /ralph:start on test project, verify AUQ options
- Verify learned behavior persists across sessions
- Verify config schema v3.2.0 compatibility

---

## Known Limitations

1. **Agents are stateless** - No persistent memory between runs (v10.2.0+ will add learning)
2. **No agent prioritization** - All agents weighted equally (future: weighted by selection rate)
3. **Discovery only** - Agents don't propose fixes (future: resolution wizard)
4. **Fixed timeout** - 15s boundary not configurable (future: per-project settings)
5. **No custom agents** - Only 3 built-in agents (future: plugin registration)

---

## Glossary

| Term | Definition |
|------|-----------|
| **Agent** | Autonomous discovery process that finds constraints (Environment, Config, Integration) |
| **Constraint** | A limitation or configuration issue that affects Ralph execution |
| **Severity** | Impact level: critical (block), high (escalate), medium (optional), low (informational) |
| **Source** | Origin of constraint discovery: scanner, env-agent, config-agent, integration-agent |
| **Aggregation** | Process of merging scanner + agent findings with deduplication |
| **Learned Behavior** | Historical tracking of user selections for optimization (v10.2.0+) |
| **Selection Rate** | Percentage of discovered constraints that user selected as forbidden/encouraged |
| **Confidence Score** | Reliability metric: 1.0 (scanner), 0.8 (agent), 0.9 (merged) |

---

## Contacts & Questions

### Design Author
**Document Set Created**: 2025-12-31

### Review Checklist
- [ ] Architecture reviewed (decision: approved/changes needed)
- [ ] Implementation roadmap approved
- [ ] Resource allocation confirmed (3 agents to build)
- [ ] Testing strategy agreed
- [ ] Timeline confirmed
- [ ] Stakeholder sign-off

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-31 | Initial design document set |
| - | TBD | Phase 1 implementation notes |
| - | TBD | Phase 2 implementation notes |
| - | TBD | Phase 3 implementation notes |

---

## Related ADRs & References

- **ADR**: `/docs/adr/2025-12-29-ralph-constraint-scanning.md` (current scanner)
- **Start Command**: `/plugins/ralph/commands/start.md` (flow definition)
- **Config Schema**: `/plugins/ralph/hooks/core/config_schema.py` (v3.0.0)
- **Ralph Discovery**: `/plugins/ralph/hooks/ralph_discovery.py` (tool detection)

---

## Document Navigation

```
You are reading: EXPLORE-AGENT-INDEX.md (this file)

Next steps:
1. For overview    → EXPLORE-AGENT-SUMMARY.md
2. For architecture → EXPLORE-AGENT-ARCHITECTURE.md
3. For implementation → EXPLORE-AGENT-IMPLEMENTATION.md
4. For full spec   → EXPLORE-AGENT-INTEGRATION-DESIGN.md

Each document is self-contained but cross-references others.
```

