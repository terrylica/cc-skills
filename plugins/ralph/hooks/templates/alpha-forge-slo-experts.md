---
name: alpha_forge_slo_experts
description: Spawn 6 parallel SLO-aligned experts for Alpha Forge value delivery
phase: slo_enforcement
adapter: alpha-forge
---

## Alpha Forge SLO Expert Consultation

**RSSI Iteration**: {{ iteration }}
**Current Phase**: {{ current_phase | default("2.0") }}
**Work Item**: {{ work_item | default("N/A") }}
**Priority**: {{ priority | default("P1") }}

---

### SLO Checkpoint Context

| Metric             | Value                      |
| ------------------ | -------------------------- | ------------- |
| ROADMAP Items Done | {{ roadmap_items_completed | default(0) }} |
| Features Added     | {{ features_added          | default(0) }} |
| Busywork Skipped   | {{ busywork_skipped        | default(0) }} |
| Checkpoints Passed | {{ checkpoints_passed      | default(0) }} |
| Checkpoints Failed | {{ checkpoints_failed      | default(0) }} |

---

### Expert Subagent Spawning (6 Experts in Parallel)

Use the Task tool to spawn ALL 6 experts **in parallel** (single message, multiple tool calls).

**Adaptive Model Selection**:

- `haiku`: Default for fast analysis
- `sonnet`: When work involves >50 lines or multiple files
- `opus`: zen-architect escalates for architectural decisions

---

**1. Zen Architect** (Priority 6 - HIGHEST, model: sonnet → opus):

````
Task(
    subagent_type="general-purpose",
    model="sonnet",
    prompt="You are the Zen Architect for Alpha Forge SLO enforcement.

CONTEXT:
- Current work item: {{ work_item }}
- Priority: {{ priority }}
- Lines changed so far: {{ lines_changed | default(0) }}
- Cross-package changes: {{ cross_package | default(false) }}

YOUR ROLE:
1. DESIGN-FIRST: Evaluate if this work needs an ADR before implementation
2. SCOPE GUARD: Flag if work exceeds 200 lines without approval
3. PATTERN CHECK: Identify if this introduces new architectural patterns
4. ROADMAP ALIGNMENT: Verify work aligns with Phase {{ current_phase }} priorities

ESCALATION TRIGGERS (if any are true, recommend ESCALATE):
- New architectural pattern not documented in existing ADRs
- Cross-package changes affecting alpha-forge-core, alpha-forge-shared, or alpha-forge-middlefreq
- >200 lines changed without explicit user approval
- Work not found in ROADMAP.md Phase {{ current_phase }}

OUTPUT (YAML):
```yaml
decision: PROCEED | ESCALATE | PAUSE_FOR_ADR
reason: 'Why this decision'
architectural_concerns: []
recommended_adr_title: 'If PAUSE_FOR_ADR, suggest ADR title'
confidence: high | medium | low
```"
)
````

---

**2. Risk Analyst** (Priority 5, model: haiku → sonnet):

````
Task(
    subagent_type="general-purpose",
    model="haiku",
    prompt="Analyze Alpha Forge work item for SLO risks and quality concerns.

WORK ITEM: {{ work_item }}

ANALYZE:
1. Is this work SLO-aligned (ROADMAP Phase {{ current_phase }} priority)?
2. Are there overfitting or regression risks?
3. Does this add meaningful test coverage?
4. Any code quality concerns?

OUTPUT (YAML):
```yaml
slo_aligned: true | false
risk_level: low | medium | high
concerns: []
recommendations:
  add: []
  modify: []
  remove: []
confidence: high | medium | low
key_insight: 'One sentence summary'
```"
)
````

---

**3. Feature Expert** (Priority 4, model: haiku → sonnet):

````
Task(
    subagent_type="general-purpose",
    model="haiku",
    prompt="Evaluate Alpha Forge feature work for value delivery.

WORK ITEM: {{ work_item }}
PRIORITY: {{ priority }}

EVALUATE:
1. Does this add meaningful functionality?
2. Is this a ROADMAP Phase {{ current_phase }} item?
3. What's the expected impact on Sharpe/CAGR/MaxDD?
4. Any feature redundancy with existing capabilities?

OUTPUT (YAML):
```yaml
is_value_work: true | false
expected_impact: 'Description of impact'
roadmap_alignment: 'Which ROADMAP item this addresses'
recommendations:
  add: []
  modify: []
  remove: []
confidence: high | medium | low
key_insight: 'One sentence summary'
```"
)
````

---

**4. Model Expert** (Priority 3, model: haiku → sonnet):

````
Task(
    subagent_type="general-purpose",
    model="haiku",
    prompt="Analyze Alpha Forge architecture and model implications.

WORK ITEM: {{ work_item }}

EVALUATE:
1. Architecture impact on existing ML models
2. Training pipeline considerations
3. Any breaking changes to existing strategies
4. Performance implications

OUTPUT (YAML):
```yaml
architecture_impact: low | medium | high
breaking_changes: []
recommendations:
  add: []
  modify: []
  remove: []
confidence: high | medium | low
key_insight: 'One sentence summary'
```"
)
````

---

**5. Data Specialist** (Priority 2, model: haiku):

````
Task(
    subagent_type="general-purpose",
    model="haiku",
    prompt="Check Alpha Forge data implications for this work.

WORK ITEM: {{ work_item }}

CHECK:
1. Data pipeline impact
2. Universe selection changes
3. Caching invalidation
4. Backward compatibility

OUTPUT (YAML):
```yaml
data_impact: low | medium | high
recommendations:
  add: []
  modify: []
  remove: []
confidence: high | medium | low
key_insight: 'One sentence summary'
```"
)
````

---

**6. Domain Expert** (Priority 1 - LOWEST, model: haiku):

````
Task(
    subagent_type="general-purpose",
    model="haiku",
    prompt="Evaluate Alpha Forge work from trading domain perspective.

WORK ITEM: {{ work_item }}

EVALUATE:
1. Execution feasibility
2. Market regime considerations
3. Transaction cost implications
4. Real-world applicability

OUTPUT (YAML):
```yaml
domain_concerns: []
recommendations:
  add: []
  modify: []
  remove: []
confidence: high | medium | low
key_insight: 'One sentence summary'
```"
)
````

---

### Conflict Resolution Protocol

When experts disagree, follow **priority order** (higher priority wins):

| Priority    | Expert          | Focus                      | Model        |
| ----------- | --------------- | -------------------------- | ------------ |
| 6 (highest) | zen-architect   | Design-first, ADR triggers | sonnet→opus  |
| 5           | risk-analyst    | SLO alignment, quality     | haiku→sonnet |
| 4           | feature-expert  | Value delivery, ROADMAP    | haiku→sonnet |
| 3           | model-expert    | Architecture, ML           | haiku→sonnet |
| 2           | data-specialist | Data pipeline              | haiku        |
| 1 (lowest)  | domain-expert   | Trading domain             | haiku        |

**Critical Override**: If zen-architect returns `PAUSE_FOR_ADR`, all other recommendations are deferred.

---

### SLO Checkpoint Evaluation

After synthesizing expert recommendations:

**PASS** (proceed with work):

- zen-architect: PROCEED
- risk-analyst: slo_aligned=true
- > =4 experts have confidence=high|medium

**FAIL** (soft correction - skip item, re-prioritize):

- zen-architect: ESCALATE or PAUSE_FOR_ADR
- risk-analyst: slo_aligned=false
- > =3 experts have concerns

**Action on PASS**:

1. Log success to research_log.md
2. Proceed with work item implementation
3. Update TodoWrite with progress

**Action on FAIL**:

1. Log warning to research_log.md
2. Skip current work item
3. Re-prioritize from ROADMAP.md
4. If PAUSE_FOR_ADR, create ADR first

---

### Expert Output Schema

All experts MUST return structured YAML output:

```yaml
# Core decision (zen-architect only)
decision: PROCEED | ESCALATE | PAUSE_FOR_ADR

# SLO alignment (risk-analyst focus)
slo_aligned: true | false
risk_level: low | medium | high

# Impact assessment
expected_impact: "Description"
architecture_impact: low | medium | high
data_impact: low | medium | high

# Recommendations
recommendations:
  add: []
  modify: []
  remove: []

concerns: []
confidence: high | medium | low
key_insight: "One sentence summary"
```

---

### Synthesis Protocol

After all 6 experts complete:

1. **Check zen-architect first** - If PAUSE_FOR_ADR, stop and create ADR
2. **Evaluate SLO checkpoint** - Aggregate expert feedback
3. **On PASS**: Proceed with work item
4. **On FAIL**: Skip, log, and get next ROADMAP item
5. **Update metrics**: TodoWrite + research_log.md + ralph-metrics.json
