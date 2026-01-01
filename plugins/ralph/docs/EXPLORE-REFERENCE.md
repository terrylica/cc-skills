# Ralph Explore Prompts - Quick Reference Card

## The 5 Prompts at a Glance

### Prompt #1: Hardcoded Values & Magic Numbers
```
🔍 Finds: /Users/username, magic numbers, fixed config paths
⚠️  Risk: Can't refactor, test variations, move projects
📋 Output: file:line, value, severity, impact
⏱️  Time: 5-10 min (depends on codebase size)
```

**Key search**:
- Absolute paths: `/Users/`, `/home/`, `~/` without variables
- Magic numbers: thresholds, timeouts, indices without names
- Fixed configs: hardcoded file paths in code

**Action if found**: `/ralph:forbid "Refactoring X (hardcoded path)"`

---

### Prompt #2: Tight Coupling & Dependency Risks
```
🔍 Finds: Circular imports, global state, pipeline ordering, schema assumptions
⚠️  Risk: Can't refactor independently, cascading failures
📋 Output: coupling type, components, risk, degrees blocked
⏱️  Time: 10-15 min
```

**Key search**:
- Import analysis: circular, heavy (>10), private modules
- Global state: variables, singletons, mutation patterns
- Schema: required fields, assumptions, alternatives
- Pipelines: "must run after X" comments, ordering constraints

**Action if found**: `/ralph:forbid "Changing component A (tightly coupled to B,C,D)"`

---

### Prompt #3: Undocumented Assumptions
```
🔍 Finds: Implicit conventions, tribal knowledge, hidden requirements
⚠️  Risk: Surprises, reverse-engineering tax, autonomy loss
📋 Output: assumption, consequence, is_documented, recommendation
⏱️  Time: 10-20 min
```

**Key search**:
- Comments: "don't change this", "assumes X", "weird because Y"
- Naming conventions: prefixes/suffixes with meaning
- Data contracts: JSON structure assumed, CSV column order
- Silent failures: broad exception catches, no error logging
- Conditionals without explanation

**Action if found**: `/ralph:forbid "Modifying X (assumption: Y)"`

---

### Prompt #4: Testing Gaps & Risky Zones
```
🔍 Finds: No tests, untested paths, edge cases, mock-heavy tests
⚠️  Risk: Can't confidently refactor, hidden breaking changes
📋 Output: location, gap type, coverage %, risk if modified
⏱️  Time: 10-15 min
```

**Key search**:
- Coverage: source files vs test files, import counts
- Paths: error handlers, conditionals, CLI arguments
- Edge cases: comments "edge case", boundaries (0, -inf, empty)
- Mocks: >70% mocks, assertions on mock calls not behavior
- Integration: API calls, database, file I/O

**Action if found**: `/ralph:forbid "Refactoring X without edge case tests"`

---

### Prompt #5: Architectural Bottlenecks
```
🔍 Finds: Monolithic design, layer violations, parallelization barriers, low extensibility
⚠️  Risk: Can't parallelize, extend, modularize, use alt algorithms
📋 Output: bottleneck type, pattern, improvements blocked, effort to unblock
⏱️  Time: 15-20 min
```

**Key search**:
- Monolithic: largest component, dependencies, feature flags
- Layers: expected UI/Logic/Data, cross-layer shortcuts
- Single points: components with zero redundancy, everything depends on
- Parallelization: sequential loops, shared mutable state, ordering
- Extensibility: plugin systems, configurable vs hardcoded

**Action if found**: `/ralph:encourage "Refactor to enable parallelization (medium effort)"`

---

## Quick Decision Matrix

| You're Worried About | Run These Prompts | Priority |
|---|---|---|
| Production breaking | #1, #2, #4 | HIGH |
| Architecture degrades | #2, #5 | MEDIUM |
| Claude inefficiency | #3, #4 | MEDIUM |
| Technical debt | All 5 | LOW |
| Fast scan | #1, #4 | NOW (15 min) |
| Complete scan | All 5 | THOROUGH (60 min) |

---

## Constraint Type → Ralph Action

```
HARDCODED VALUES
  ├─ CRITICAL: /ralph:forbid "Refactoring paths"
  └─ HIGH: /ralph:encourage "Extract to environment variables"

TIGHT COUPLING
  ├─ HIGH: /ralph:forbid "Changing schema independently"
  └─ MEDIUM: /ralph:encourage "Add integration tests"

UNDOCUMENTED
  ├─ HIGH: /ralph:forbid "Modifying implicit assumptions"
  └─ MEDIUM: /ralph:encourage "Document in docstring"

TESTING GAPS
  ├─ HIGH: /ralph:forbid "Refactoring untested code"
  └─ MEDIUM: /ralph:encourage "Write edge case tests first"

ARCHITECTURAL
  ├─ MEDIUM: /ralph:forbid "Parallel feature experiments"
  └─ LOW: /ralph:encourage "Refactor to enable parallelization"
```

---

## Workflow: Run All 5 Prompts

```
Day 1 Morning: Prompts #1 (hardcodes) + #4 (tests)
  ↓
  → Create immediate forbid list (quick wins, high risk)
  ↓

Day 1 Afternoon: Prompts #2 (coupling) + #5 (architecture)
  ↓
  → Medium-term improvements
  ↓

Day 1 Evening: Prompt #3 (assumptions)
  ↓
  → Documentation tasks
  ↓

Day 2: Create comprehensive forbidden/encouraged lists
  ↓

Day 3: Run /ralph:start with optimized guidance
```

---

## Output Format (All Prompts)

Every prompt should return structured findings like:

```json
{
  "constraint_type": "hardcoded_value|tight_coupling|undocumented_assumption|testing_gap|architectural_bottleneck",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "location": "file:line or description",
  "finding": "What was discovered",
  "impact": "Why it matters for Claude's autonomy",
  "recommendation": "How to fix or work around it"
}
```

---

## Integration Checklist

- [ ] Run 5 prompts (or subset based on priority)
- [ ] Review findings, note CRITICAL/HIGH items
- [ ] Extract forbidden items: `/ralph:forbid "..."`
- [ ] Extract encouraged items: `/ralph:encourage "..."`
- [ ] Create `.claude/ralph-config.json` with guidance
- [ ] Start Ralph loop: `/ralph:start`

---

## Common Results (By Project Type)

### Web App (React/TypeScript)
```
Most common: #1 (env paths), #4 (component tests)
Risk: Untested components, hardcoded API endpoints
```

### Data Pipeline (Python)
```
Most common: #2 (pipeline order), #5 (sequential processing)
Risk: Tight coupling between transformers, no parallelization
```

### ML Project (PyTorch)
```
Most common: #1 (data paths), #4 (untested configs)
Risk: Hardcoded data paths, untested edge cases
```

### Microservices
```
Most common: #2 (API contracts), #5 (extensibility)
Risk: Service interdependencies, breaking schema changes
```

### Monolith
```
Most common: #5 (monolithic), #2 (coupling)
Risk: Everything depends on everything, can't change safely
```

---

## Constraints Override Degrees of Freedom

### Without Explore Prompts

Claude has high degrees of freedom but **discovers constraints by failing**:
- Tries to refactor paths → Hits hardcoded assumption → Revert
- Tries to refactor component → Breaks 3 dependents → Revert
- Tries to improve → Fails untested code → Revert
- **Result**: Iteration waste, surprises, inefficiency

### With Explore Prompts

Claude has **constrained but optimized** degrees of freedom:
- Knows which changes are forbidden (avoids them)
- Knows which improvements are encouraged (prioritizes them)
- Knows what assumptions are implicit (doesn't violate them)
- **Result**: Higher success rate, no surprises, efficient work

---

## Files

| File | Use For |
|------|---------|
| EXPLORE-GUIDE.md | Getting started |
| EXPLORE-AGENT-PROMPTS.md | Full understanding |
| EXPLORE-TASK-PROMPTS.txt | Copy/paste ready |
| EXPLORE-EXAMPLES.md | See real examples |
| EXPLORE-REFERENCE.md | This file (quick lookup) |

---

## Key Insight

**Constraints aren't bad** — they're information.

Discovering constraints lets Ralph:
1. **Block breaking changes** (prevents failures)
2. **Guide Claude toward improvements** (improves autonomy)
3. **Accumulate knowledge** (discovers what matters)
4. **Optimize degrees of freedom** (best possible work)

---

**Start here**: Copy one prompt from EXPLORE-TASK-PROMPTS.txt and run it.
