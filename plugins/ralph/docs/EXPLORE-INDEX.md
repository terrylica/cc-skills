# Ralph Explore Agents - Complete Documentation Index

> **Purpose**: Design prompts for specialized Explore sub-agents that discover constraints limiting Claude's degrees of freedom during Ralph loops.

> **Status**: Complete - 5 specialized prompts + 3 supporting documents

---

## Quick Start

**Copy-paste ready prompts**: [EXPLORE-TASK-PROMPTS.txt](./EXPLORE-TASK-PROMPTS.txt)

**Understanding first**: [EXPLORE-GUIDE.md](./EXPLORE-GUIDE.md)

**Quick lookup**: [EXPLORE-REFERENCE.md](./EXPLORE-REFERENCE.md)

---

## Document Map

### Core Deliverables (Ready to Use)

#### 1. **EXPLORE-AGENT-PROMPTS.md** — Full Specifications
- **What it is**: Complete prompt specifications for 5 specialized agents
- **Length**: 419 lines
- **Contains**:
  - Prompt #1: Hardcoded Values & Magic Numbers Scanner
  - Prompt #2: Tightly Coupled Components & Dependency Risks
  - Prompt #3: Undocumented Assumptions & Implicit Conventions
  - Prompt #4: Testing Gaps & Risky Modification Zones
  - Prompt #5: Architectural Bottlenecks & Rigid Structures
- **For each prompt**: Purpose, what it finds, why it matters, search strategy, output format
- **Use when**: You want detailed understanding of each agent's focus

#### 2. **EXPLORE-TASK-PROMPTS.txt** — Copy/Paste Format
- **What it is**: Condensed versions of 5 prompts ready for Task tool
- **Length**: 220 lines
- **Format**: Plain text, one prompt per section
- **Use when**: Running a prompt immediately (fastest path)
- **How**: Copy the prompt section, paste into `/task` command

#### 3. **EXPLORE-EXAMPLES.md** — Real Code Walkthroughs
- **What it is**: Concrete examples from cc-skills repository
- **Length**: 445 lines
- **Contains**:
  - Example 1: Hardcoded home directory in Ralph scanner
  - Example 2: Tight coupling in Ralph hook pipeline
  - Example 3: Undocumented busywork assumptions
  - Example 4: Testing gaps in Stop hook edge cases
  - Example 5: State management bottleneck (single-threaded)
- **Shows**: What each prompt finds, how to interpret results, Ralph response
- **Use when**: Understanding how prompts work on real code

### Navigation & Guides

#### 4. **EXPLORE-GUIDE.md** — Getting Started
- **What it is**: Overview and entry point
- **Length**: 237 lines
- **Contains**:
  - Problem statement
  - Which document to read when
  - The 5 prompts at a glance
  - Quick start options (understand first, jump in, full assessment)
  - Severity levels
  - Integration with Ralph loop
  - Common patterns
- **Use when**: First time here, deciding how to proceed

#### 5. **EXPLORE-REFERENCE.md** — Quick Lookup Card
- **What it is**: At-a-glance reference
- **Length**: 268 lines
- **Contains**:
  - All 5 prompts summarized (2-3 lines each)
  - Quick decision matrix (which prompts to run)
  - Constraint type → Ralph action mapping
  - Workflow schedule
  - Output format template
  - Integration checklist
  - Common results by project type
- **Use when**: You know what you want but need quick facts

### Architecture & Implementation (Reference)

These documents describe the full system architecture:

#### 6. **EXPLORE-AGENT-ARCHITECTURE.md** (615 lines)
System design: how agents fit into Ralph, interaction patterns, state management

#### 7. **EXPLORE-AGENT-INTEGRATION-DESIGN.md** (589 lines)
Integration patterns: how findings feed into forbidden/encouraged, AUQ flow, feedback loops

#### 8. **EXPLORE-AGENT-IMPLEMENTATION.md** (989 lines)
Implementation guide: Python templates for each agent type, testing patterns, examples

---

## The 5 Explore Agents Explained

| Agent | Finds | Blocks | Severity |
|-------|-------|--------|----------|
| **#1 Hardcoded** | Absolute paths, magic numbers, fixed configs | Refactoring, architecture, testing variations | CRITICAL→HIGH |
| **#2 Coupling** | Circular imports, global state, pipeline order | Safe refactoring, modularization, independence | HIGH→MEDIUM |
| **#3 Undocumented** | Implicit conventions, tribal knowledge, assumptions | Autonomy, exploration, error recovery | HIGH→MEDIUM |
| **#4 Testing** | Untested paths, edge cases, missing coverage | Confident changes, refactoring, safety | HIGH→MEDIUM |
| **#5 Bottleneck** | Monolithic design, layers, parallelization barriers | Parallel work, extensibility, alternatives | MEDIUM→LOW |

---

## Using These Documents

### Scenario 1: "I want to understand the concept"
1. Read EXPLORE-GUIDE.md (5 min)
2. Pick one example from EXPLORE-EXAMPLES.md (10 min)
3. Read EXPLORE-AGENT-PROMPTS.md section on that agent (10 min)
**Total: 25 minutes**

### Scenario 2: "I need to run a prompt right now"
1. Open EXPLORE-TASK-PROMPTS.txt
2. Copy Prompt #1 (or whichever is relevant)
3. Paste into `/task` command
4. Review output, create `/ralph:forbid` items
**Total: 10 minutes**

### Scenario 3: "I want comprehensive assessment"
1. Read EXPLORE-GUIDE.md (5 min)
2. Review decision matrix in EXPLORE-REFERENCE.md (2 min)
3. Run all 5 prompts from EXPLORE-TASK-PROMPTS.txt (90 min)
4. Interpret findings using EXPLORE-EXAMPLES.md patterns (30 min)
5. Create forbidden/encouraged lists (20 min)
6. Start Ralph loop with guidance (5 min)
**Total: 150 minutes**

### Scenario 4: "I want to understand the full system"
1. Read EXPLORE-GUIDE.md (5 min)
2. Read EXPLORE-AGENT-PROMPTS.md (30 min)
3. Study EXPLORE-EXAMPLES.md in depth (30 min)
4. Review EXPLORE-AGENT-ARCHITECTURE.md (20 min)
5. Review EXPLORE-AGENT-INTEGRATION-DESIGN.md (15 min)
**Total: 100 minutes**

### Scenario 5: "I want to implement this myself"
1. Read EXPLORE-AGENT-IMPLEMENTATION.md (45 min)
2. Study Python templates (30 min)
3. Implement for your use case (120+ min)
**Total: Variable**

---

## Quick Reference by Document Type

### If You Want To...

| Goal | Document | Section |
|------|----------|---------|
| Understand concept | EXPLORE-GUIDE.md | All |
| Learn one agent | EXPLORE-EXAMPLES.md | Example N |
| Run a prompt | EXPLORE-TASK-PROMPTS.txt | Prompt N |
| Quick facts | EXPLORE-REFERENCE.md | All |
| Deep dive one agent | EXPLORE-AGENT-PROMPTS.md | Agent N |
| Understand workflow | EXPLORE-GUIDE.md | Integration with Ralph Loop |
| See it work in code | EXPLORE-EXAMPLES.md | Example N walkthrough |
| Make design decisions | EXPLORE-AGENT-ARCHITECTURE.md | Architecture sections |
| Implement in Python | EXPLORE-AGENT-IMPLEMENTATION.md | Implementation templates |
| Integrate with Ralph | EXPLORE-AGENT-INTEGRATION-DESIGN.md | Integration patterns |

---

## What Each Prompt Discovers

### Prompt #1: Hardcoded Values & Magic Numbers
**Discovers**: Constraints preventing architecture changes, testing variations, environment portability

**Search strategy**:
- Absolute paths: `/Users/`, `/home/`, hardcoded env-specific paths
- Magic numbers: thresholds, timeouts, array indices without names
- Fixed configs: hardcoded file paths in code

**Output**: file:line, value, severity, impact, recommendation

**Example**:
```json
{
  "constraint_type": "hardcoded_value",
  "file": "config.py:42",
  "value": "/Users/terry/data",
  "severity": "CRITICAL",
  "impact": "Project won't run on other machines or users",
  "recommendation": "Extract to os.environ.get('DATA_PATH')"
}
```

---

### Prompt #2: Tightly Coupled Components
**Discovers**: Constraints preventing safe refactoring, independent component changes, modularization

**Search strategy**:
- Circular imports: A→B→A
- Heavy dependencies: Files with >10 imports
- Global state: Variables, singletons, mutations
- Pipeline ordering: "must run after X" comments
- Schema assumptions: Required fields, structure contracts

**Output**: components, coupling type, risk, degrees blocked, recommendation

---

### Prompt #3: Undocumented Assumptions
**Discovers**: Knowledge gaps that force reverse-engineering, reduce autonomy, cause surprises

**Search strategy**:
- Comment analysis: "don't change X", "assumes Y"
- Naming conventions: Prefixes/suffixes with meaning
- Data contracts: Assumed JSON structure, CSV column order
- Silent failures: Broad exception catches
- Conditional logic: Branches without explanation

**Output**: assumption, consequence, is_documented, recommendation

---

### Prompt #4: Testing Gaps
**Discovers**: Code regions where modifications are risky, forcing test-first approach

**Search strategy**:
- Coverage gaps: Source files without tests
- Untested paths: Error handlers, conditionals, rare cases
- Edge cases: Boundaries (0, -inf, empty)
- Mock-heavy tests: Assertions on mocks not behavior
- Integration points: API/database calls

**Output**: location, gap type, coverage %, risk, blocks refactoring of

---

### Prompt #5: Architectural Bottlenecks
**Discovers**: Design rigidity preventing parallelization, extensibility, alternative algorithms

**Search strategy**:
- Monolithic design: Large components, dependencies, feature flags
- Layer violations: UI calling database directly
- Single points of failure: Components with zero redundancy
- Parallelization barriers: Sequential loops, shared mutable state
- Extensibility: Plugin systems, configurable vs hardcoded

**Output**: bottleneck type, current design, improvements blocked, effort to unblock

---

## Integration with Ralph Loop

### Phase: OBSERVE
```
Run Explore prompts to catalog constraints
Output: List of findings with severity and impact
```

### Phase: ORIENT
```
Categorize by severity and importance
Map: Which constraints block which improvements
Decision: What to tackle first
```

### Phase: DECIDE
```
Decide what's forbidden: High-risk changes in constrained areas
Decide what's encouraged: Constraint resolutions with high impact
Output: /ralph:forbid and /ralph:encourage lists
```

### Phase: ACT
```
Execute with optimized guidance
Claude avoids forbidden zones, prioritizes encouraged items
Degrees of freedom are optimized for productive work
```

---

## Severity Framework

| Severity | Definition | Ralph Action | Example |
|----------|-----------|---|---------|
| **CRITICAL** | Will break on another machine/user/config | Block loop start | `/Users/terry/` hardcoded in 3 files |
| **HIGH** | Might cause production failure | Pre-populate forbid list, recommend action | Untested error handler |
| **MEDIUM** | Worth knowing about, optional action | Show in deep-dive, informational | Missing edge case comment |
| **LOW** | Just noting existence | Log only, proceed normally | Non-Ralph hook detected |

---

## Files in This Delivery

```
plugins/ralph/docs/
├── EXPLORE-INDEX.md                  ← You are here
├── EXPLORE-GUIDE.md                  ← Start here
├── EXPLORE-REFERENCE.md              ← Quick lookup
├── EXPLORE-TASK-PROMPTS.txt          ← Copy/paste prompts
├── EXPLORE-AGENT-PROMPTS.md          ← Full specifications
├── EXPLORE-EXAMPLES.md               ← Real code examples
├── EXPLORE-AGENT-ARCHITECTURE.md     ← System design
├── EXPLORE-AGENT-INTEGRATION-DESIGN.md ← Integration patterns
└── EXPLORE-AGENT-IMPLEMENTATION.md   ← Python implementation
```

**Total**: 3,782 lines of documentation + ready-to-use prompts

---

## Next Steps

### For Immediate Use
1. Go to EXPLORE-TASK-PROMPTS.txt
2. Copy Prompt #1 (Hardcoded Values)
3. Paste into `/task` command
4. Review findings

### For Understanding
1. Read EXPLORE-GUIDE.md
2. Pick one example from EXPLORE-EXAMPLES.md
3. Read corresponding section in EXPLORE-AGENT-PROMPTS.md

### For Comprehensive Assessment
1. Review EXPLORE-REFERENCE.md decision matrix
2. Run all 5 prompts from EXPLORE-TASK-PROMPTS.txt
3. Use EXPLORE-EXAMPLES.md to interpret results
4. Create forbidden/encouraged lists
5. Run `/ralph:start` with optimized guidance

### For Implementation
1. Read EXPLORE-AGENT-ARCHITECTURE.md
2. Read EXPLORE-AGENT-INTEGRATION-DESIGN.md
3. Follow templates in EXPLORE-AGENT-IMPLEMENTATION.md
4. Implement for your system

---

## Design Philosophy

These prompts embody Ralph's core principle: **Constraints aren't bad — they're information.**

By discovering constraints before they cause failures:
1. **Prevent breaking changes** (forbidden zones)
2. **Guide productive work** (encouraged priorities)
3. **Reduce surprises** (documented assumptions)
4. **Improve efficiency** (avoid risky paths)
5. **Unlock potential** (unblock bottlenecks)

Claude's degrees of freedom are **constrained by information, not chaos**.

---

## Related Resources

- **Ralph Plugin**: [/plugins/ralph/README.md](/plugins/ralph/README.md)
- **Ralph Mental Model**: [/plugins/ralph/MENTAL-MODEL.md](/plugins/ralph/MENTAL-MODEL.md)
- **Constraint Scanner**: [/plugins/ralph/scripts/constraint-scanner.py](/plugins/ralph/scripts/constraint-scanner.py)
- **Constraint Scanning ADR**: [/docs/adr/2025-12-29-ralph-constraint-scanning.md](/docs/adr/2025-12-29-ralph-constraint-scanning.md)

---

**Version**: 1.0
**Status**: Ready for use
**Last updated**: 2025-12-31

---

## Summary Table

| Document | Lines | Purpose | For | Time |
|----------|-------|---------|-----|------|
| EXPLORE-AGENT-PROMPTS.md | 419 | Full agent specs | Understanding | 30 min |
| EXPLORE-TASK-PROMPTS.txt | 220 | Copy/paste ready | Immediate use | 10 min |
| EXPLORE-EXAMPLES.md | 445 | Real code | Interpretation | 30 min |
| EXPLORE-GUIDE.md | 237 | Getting started | Entry point | 10 min |
| EXPLORE-REFERENCE.md | 268 | Quick lookup | Fact checking | 5 min |
| EXPLORE-AGENT-ARCHITECTURE.md | 615 | System design | Deep understanding | 30 min |
| EXPLORE-AGENT-INTEGRATION-DESIGN.md | 589 | Integration | Implementation | 25 min |
| EXPLORE-AGENT-IMPLEMENTATION.md | 989 | Python templates | Building | 45 min |

**→ Start with EXPLORE-GUIDE.md or EXPLORE-TASK-PROMPTS.txt**
