# Ralph Explore Agent Guide
## Discovering Constraints on Claude's Degrees of Freedom

Quick start for discovering and eliminating constraints during Ralph autonomous loops.

---

## What Problem Do We Solve?

Ralph's eternal loop gives Claude continuous work opportunities, but **constraints limit what Claude can safely do**:

- Hardcoded paths block architecture refactoring
- Untested code blocks improvements
- Tight coupling prevents independent changes
- Undocumented assumptions cause surprises
- Architectural rigidity prevents categories of work

**The Explore Agents solve this**: Use 5 specialized scanning prompts to discover constraints, then forbid risky changes and encourage constraint resolution.

---

## Three Documents Included

### 1. **EXPLORE-AGENT-PROMPTS.md** (Comprehensive)
- Full prompt specifications for each of 5 agents
- How each constraint limits degrees of freedom
- Structured output format for each finding
- Integration with Ralph loop phases (OBSERVE → ORIENT → DECIDE → ACT)
- Usage patterns and feedback loops

**Use when**: You want detailed understanding of what each prompt discovers and how to interpret results.

### 2. **EXPLORE-TASK-PROMPTS.txt** (Quick Reference)
- Condensed prompts ready to copy/paste into Task tool
- One prompt per section, minimal commentary
- Key search strategies for each category
- Quick output format for each constraint type

**Use when**: You want to immediately run a scan. Copy paste each prompt into `/task` command.

### 3. **EXPLORE-EXAMPLES.md** (Real Code)
- Live examples from cc-skills repository
- Shows what each prompt finds in real projects
- Demonstrates Ralph response (`/ralph:forbid`, `/ralph:encourage`)
- How constraints affect practical development decisions
- Integration workflow across multiple days

**Use when**: You want to see how this works on actual code before running on your project.

---

## Quick Start

### Option A: Understand First (30 minutes)

1. Read EXPLORE-AGENT-PROMPTS.md intro section
2. Skim one example from EXPLORE-EXAMPLES.md
3. Decide which constraint category is most important for your project
4. Run that one prompt

### Option B: Jump In (5 minutes)

1. Open EXPLORE-TASK-PROMPTS.txt
2. Copy Prompt #1 (Hardcoded Values)
3. Paste into `/task` command
4. Review findings, create `/ralph:forbid` items

### Option C: Full Assessment (2 hours)

1. Run all 5 prompts sequentially
2. Review EXPLORE-EXAMPLES.md for interpretation patterns
3. Categorize findings by severity
4. Create comprehensive forbidden/encouraged lists
5. Run Ralph loop with optimized guidance

---

## The 5 Explore Prompts

| # | Name | Finds | Blocks |
|---|------|-------|--------|
| 1 | Hardcoded Values Scanner | Absolute paths, magic numbers, config hardcoding | Refactoring, architecture changes, testing variations |
| 2 | Tight Coupling | Circular imports, global state, pipeline ordering | Safe independent refactoring, modularization |
| 3 | Undocumented Assumptions | Implicit conventions, hidden knowledge, tribal knowledge | Safe exploration, autonomy, error recovery |
| 4 | Testing Gaps | Untested paths, edge cases, missing coverage | Confident changes, refactoring, feature development |
| 5 | Architectural Bottlenecks | Monolithic design, layer violations, parallelization barriers | Parallel work, extensibility, alternative algorithms |

---

## Severity Levels

Ralph uses 4-tier severity for constraints:

| Severity | Meaning | Ralph Response |
|----------|---------|---|
| **CRITICAL** | This WILL break on another machine | Block loop start, must be fixed first |
| **HIGH** | This MIGHT cause problems | Pre-populate forbidden list, recommend action |
| **MEDIUM** | Something to be aware of | Show in deep-dive option, informational |
| **LOW** | Just noting this exists | Log only, proceed normally |

---

## Integration with Ralph Loop

### Phase 1: OBSERVE (Run Explore Prompts)
```bash
/task "Prompt #1: Hardcoded Values"
/task "Prompt #4: Testing Gaps"
# Results show what constraints exist
```

### Phase 2: ORIENT (Categorize by Impact)
```bash
# High severity + blocks important work → HIGH priority
# Medium severity + nice to have → LOW priority
```

### Phase 3: DECIDE (Create Guidance)
```bash
/ralph:forbid "High-risk changes that hit constraints"
/ralph:encourage "Constraint resolutions that improve degrees of freedom"
```

### Phase 4: ACT (Optimized Loop)
```bash
/ralph:start
# Claude now works with precise guidance
# - Forbidden zones prevent failures
# - Encouraged items prioritize constraint resolution
```

---

## Choosing Which Prompts to Run

### If You're Concerned About...

**Breaking changes in production?** → Run Prompts #1, #2, #4
- Hardcoded paths can break on new machines
- Tight coupling can cascade failures
- Untested code breaks silently

**Architecture getting worse?** → Run Prompts #2, #5
- Tight coupling accumulates over time
- Bottlenecks multiply as team grows

**Claude working inefficiently?** → Run Prompts #3, #4
- Undocumented assumptions force reverse-engineering
- Testing gaps force redundant test-writing

**Managing technical debt?** → Run All 5
- Comprehensive assessment of constraints
- Prioritized list of improvements
- Clear improvement path

---

## Expected Outcomes

### After Running Prompts

You will have:
- **Constraint catalog**: What limits degrees of freedom
- **Severity mapping**: What's critical vs nice-to-have
- **Degrees of freedom blocked**: What improvements are impossible/risky without fixes
- **Recommendations**: How to unblock each constraint

### After Configuring Ralph

Claude will:
- **Avoid forbidden zones**: No breaking changes in constrained areas
- **Prioritize improvements**: Encouraged items rise to top of work list
- **Work efficiently**: Avoid surprises from undocumented assumptions
- **Make safe changes**: Testing guidance prevents risky refactoring
- **Unlock potential**: Architecture improvements enable new categories of work

---

## Common Patterns

### Pattern 1: Hardcoded Home Directory
**Finding**: `/Users/terry/` hardcoded in 3 config files
**Severity**: CRITICAL (breaks on other machines)
**Solution**: Extract to `$HOME` environment variable
**Ralph Action**: Forbid until extracted, encourage extraction

### Pattern 2: Untested Error Handler
**Finding**: File permission error handler never tested
**Severity**: HIGH (production failures possible)
**Solution**: Write edge case tests first
**Ralph Action**: Forbid refactoring error handling without tests, encourage test-first approach

### Pattern 3: Implicit Ordering
**Finding**: "Step 1 must run before Step 2" only in comments
**Severity**: MEDIUM (easy to break with refactoring)
**Solution**: Document in docstring, or restructure to enforce ordering
**Ralph Action**: Forbid reordering without review, encourage documentation

### Pattern 4: Monolithic Service
**Finding**: 5000+ line service handling 3 independent concerns
**Severity**: MEDIUM (blocks parallelization, extensibility)
**Solution**: Refactor to separate modules, add abstraction layer
**Ralph Action**: Encourage modularization, enable parallel feature development

---

## Files

```
plugins/ralph/docs/
├── EXPLORE-GUIDE.md                  ← You are here
├── EXPLORE-AGENT-PROMPTS.md          ← Detailed specifications (3000+ words)
├── EXPLORE-TASK-PROMPTS.txt          ← Quick copy-paste format (500 words)
└── EXPLORE-EXAMPLES.md               ← Real code walkthroughs (2000+ words)
```

---

## Related

- **Ralph Plugin**: [/plugins/ralph/README.md](/plugins/ralph/README.md)
- **Constraint Scanner**: [/plugins/ralph/scripts/constraint-scanner.py](/plugins/ralph/scripts/constraint-scanner.py) - Automated hardcode detection
- **Ralph Mental Model**: [/plugins/ralph/MENTAL-MODEL.md](/plugins/ralph/MENTAL-MODEL.md#constraint-scanner-v300)
- **ADR**: [/docs/adr/2025-12-29-ralph-constraint-scanning.md](/docs/adr/2025-12-29-ralph-constraint-scanning.md)

---

## Next Steps

1. Choose your constraint priority (above)
2. Select corresponding Explore prompt(s)
3. Follow the prompt's search strategy
4. Review findings using EXPLORE-EXAMPLES.md as interpretation guide
5. Create `/ralph:forbid` and `/ralph:encourage` items
6. Run `/ralph:start` with optimized guidance

**Estimated time**: 30-120 minutes depending on project size and how many prompts you run.
