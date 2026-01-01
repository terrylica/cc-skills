# Ralph Explore Agent Prompts - Real Examples
## Using cc-skills Repository as Reference Cases

This document shows how the 5 Explore prompts would work on actual code, using the cc-skills repository as reference examples.

---

## Example 1: Hardcoded Values & Magic Numbers Scanner

### Real Finding in cc-skills

**Location**: `plugins/ralph/scripts/constraint-scanner.py:166-169`

```python
patterns = [
    (r"/Users/[^/]+/", Severity.HIGH, "Absolute user path"),
    (r"/home/[^/]+/", Severity.HIGH, "Absolute home path"),
    (rf"{re.escape(home_dir)}", Severity.CRITICAL, "Current user home path"),
]
```

### Scanner Output

```json
{
  "constraint_type": "hardcoded_value",
  "severity": "CRITICAL",
  "category": "path",
  "file": "plugins/ralph/scripts/constraint-scanner.py",
  "line": 169,
  "value": "/Users/terryli/",
  "description": "Current user home path (/Users/terryli/) in config files",
  "impact": "Prevents Claude from: refactoring paths, testing on other machines, moving project to different computer",
  "recommendation": "Already handled by constraint-scanner.py - but if found in actual .claude/settings.json or pyproject.toml, must extract to $HOME env var",
  "workaround": "All .claude/ config files should use ~ or $HOME instead"
}
```

### Ralph Response

```bash
/ralph:forbid "Modifying .claude/settings.json (contains /Users/terryli/ hardcoded paths)"
/ralph:encourage "Extract any paths to environment variables during refactoring"
```

---

## Example 2: Tightly Coupled Components & Dependency Risks

### Real Finding in cc-skills

**Location**: Hook coordination in Ralph (5 files)

The Ralph Stop hook has a tight coupling between:
- `loop-until-done.py` (Stop hook)
- `template_loader.py` (template rendering)
- `ralph-unified.md` (template)
- `.claude/ralph-config.json` (guidance)
- `core/config_schema.py` (validation)

**Dependency chain**:
```
loop-until-done.py
  → reads ralph-config.json
    → validated by config_schema.py
  → injects into ralph_context dict
    → template_loader.py extracts forbidden/encouraged
      → renders ralph-unified.md
        → returns JSON with embedded guidance
```

### Scanner Output

```json
{
  "constraint_type": "tight_coupling",
  "severity": "HIGH",
  "components": [
    "loop-until-done.py",
    "template_loader.py",
    "config_schema.py",
    "ralph-config.json",
    "ralph-unified.md"
  ],
  "coupling_type": "pipeline_order",
  "location": "plugins/ralph/hooks/",
  "risk": "Changing config schema requires updates to: template_loader.py extraction logic, loop-until-done.py injection points, ralph-unified.md rendering",
  "degrees_of_freedom_blocked": "Cannot change guidance format independently of template rendering",
  "pipeline_risk": [
    "If config_schema.py validation changes, loop-until-done.py may fail to load config",
    "If template_loader.py extraction fails silently, guidance won't appear in template",
    "If ralph-unified.md removes a variable, template_loader extraction breaks"
  ],
  "recommendation": "Add integration tests that verify: config load → extraction → template render → output contains guidance"
}
```

### Ralph Response

```bash
/ralph:forbid "Changing Ralph config schema without updating both template_loader.py and template (tight coupling)"
/ralph:encourage "Add integration tests for config→template pipeline (3 components)"
```

### Mitigation Strategy

A Claude session could safely:
1. Add logging at each pipeline step (no schema changes)
2. Add tests without changing structure (validates coupling)
3. Extract common patterns to utility functions (improves maintainability)

But Claude cannot safely (without breaking the pipeline):
1. Change config schema without updating template extraction
2. Rename guidance arrays without finding all usage sites

---

## Example 3: Undocumented Assumptions & Implicit Conventions

### Real Finding in cc-skills

**Location**: `plugins/ralph/MENTAL-MODEL.md` and `plugins/ralph/README.md`

The Ralph behavior has undocumented assumptions about "busywork" that's only defined in one place:

**Hardcoded in code**:
```python
# plugins/ralph/scripts/constraint-scanner.py:311-351
def get_builtin_busywork() -> list[BuiltinBusywork]:
    """Get built-in busywork patterns from alpha_forge_filter.py categories."""
    return [
        BuiltinBusywork(
            id="busywork-lint",
            name="Linting/style rules",
            description="Ruff, Black, isort formatting suggestions",
        ),
        # ... 9 more busywork types ...
    ]
```

**Assumption**: "Linting is always busywork, research is never busywork"

But this is hardcoded and not in documentation.

### Scanner Output

```json
{
  "constraint_type": "undocumented_assumption",
  "severity": "MEDIUM",
  "location": "plugins/ralph/scripts/constraint-scanner.py:311-351",
  "assumption": "Linting, documentation, test coverage, CI/CD are always 'busywork' and should be deprioritized in research loops",
  "consequence_if_violated": "If Claude treats linting as valuable work, Ralph loop will discourage it. If a project legitimately needs style fixes, Ralph configuration cannot express 'please do format this'",
  "discovery_method": "Found by reading constraint-scanner.py - hardcoded categories",
  "is_documented": false,
  "documentation_gap": "The list of busywork categories is in constraint-scanner.py but not in MENTAL-MODEL.md or README.md",
  "recommendation": "Document in MENTAL-MODEL.md: 'Ralph's busywork filter treats these as low-value: [list]. Projects can override via /ralph:encourage'",
  "impact_on_degrees_of_freedom": "Projects that DO care about linting/docs cannot configure Ralph to encourage those. Cannot override hardcoded list."
}
```

### Ralph Response

```bash
/ralph:forbid "Treating linting as mandatory (hardcoded busywork assumption, not documented)"
/ralph:encourage "Document busywork categories in MENTAL-MODEL.md with override instructions"
```

### Code Discovery

The assumption lives in multiple places:
1. **constraint-scanner.py**: Hardcoded busywork list
2. **alpha_forge_filter.py**: May have related filtering (not checked)
3. **README.md**: Says "FORBIDDEN: linting, formatting..." (partially documented)
4. **MENTAL-MODEL.md**: References busywork but doesn't list categories

This scattered documentation is the constraint: if Claude needs to add a busywork category, they must update 3-4 files without clear guidance.

---

## Example 4: Testing Gaps & Risky Modification Zones

### Real Finding in cc-skills

**Location**: Ralph hooks test suite

The Ralph Stop hook has **integration test coverage** but some edge cases are untested:

```
✓ TESTED:
- Normal iteration flow (loop continues)
- Task completion detection (loop stops after min_hours)
- Idle detection (loop pivots to exploration)
- Config loading from disk

✗ UNTESTED:
- Race condition: what if config file is deleted between loop iterations?
- Partial config: what if guidance array is malformed JSON?
- Permission error: what if ralph-config.json becomes read-only?
- Symlink following: what if project dir is a symlink to another repo?
```

### Scanner Output

```json
{
  "constraint_type": "testing_gap",
  "severity": "HIGH",
  "location": "plugins/ralph/hooks/loop-until-done.py",
  "gap_type": "edge_cases",
  "test_coverage": "~70% (normal paths tested, edge cases not)",
  "test_files": [
    "plugins/ralph/hooks/tests/test_hook_emission.py",
    "plugins/ralph/hooks/tests/test_utils.py"
  ],
  "untested_edge_cases": [
    "Config file deleted between iterations",
    "Malformed guidance JSON",
    "File permission errors",
    "Symlink resolution failures",
    "Concurrent sessions with same project_hash"
  ],
  "risk_if_modified": "If Claude refactors loop-until-done.py to handle more edge cases, there's no test coverage for new paths. Breaking change could go undetected until Ralph loop fails in production.",
  "blocks_refactoring_of": [
    "Error handling improvements",
    "Robustness to filesystem changes",
    "Concurrent session handling"
  ],
  "recommendation": "Add integration tests for 5 edge cases above before refactoring error handling"
}
```

### Ralph Response

```bash
/ralph:forbid "Refactoring loop-until-done.py error handling (edge cases untested: config deletion, permission errors)"
/ralph:encourage "Write integration tests for file permission/deletion edge cases (enables safer refactoring)"
```

### How This Blocks Claude

If Claude wants to improve error handling in `loop-until-done.py`:

1. **Forbidden approach**: Refactor the existing error handling → risk: untested edge cases break
2. **Encouraged approach**:
   - First: Write tests for edge cases
   - Then: Refactor with confidence

This transforms a risky change (forbidden) into a safe sequence (encouraged).

---

## Example 5: Architectural Bottlenecks & Rigid Structures

### Real Finding in cc-skills

**Location**: Ralph state management architecture

Ralph state flow is currently sequential and cannot be easily parallelized:

```
┌─────────────────────────────────┐
│ /ralph:start                    │
│ (Create .claude/loop-enabled)   │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Iteration N                     │
│ (Claude works on task)          │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Stop Hook Fires                 │
│ (Check state, read config)      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Iteration N+1                   │
│ (Claude continues)              │
└─────────────────────────────────┘
```

**Bottleneck**: All state reads/writes are serial. Cannot parallelize:
- Multiple worktrees updating the same session state
- Multiple feature explorations in parallel
- Validation running while Claude works

### Scanner Output

```json
{
  "constraint_type": "architectural_bottleneck",
  "severity": "MEDIUM",
  "bottleneck_type": "parallelization_barrier",
  "location": "plugins/ralph/hooks/loop-until-done.py (state management)",
  "current_design": "Stop hook reads .claude/ralph-config.json, updates ~/.claude/automation/sessions/*.json, returns prompt. Sequence is: read → check → update → render → return",
  "parallelization_barrier": [
    "File I/O serialization: config read blocks template rendering",
    "Shared state: all sessions write to same sessions/ directory",
    "Order dependency: must read config BEFORE injecting into template"
  ],
  "classes_of_improvements_blocked": [
    "Parallel feature exploration (can't safely fork state)",
    "Background validation (conflicts with active session updates)",
    "Multi-worktree concurrent operations (would need file locking)"
  ],
  "current_pattern": "Synchronous pipeline: read config → validate → inject → render",
  "alternative_pattern": "Could use Redis/SQLite for state (enables concurrent access), message queue for hook communication",
  "architectural_change_needed": "Add file locking (filelock dependency already present) to enable concurrent sessions",
  "estimated_effort": "medium (2-3 days: add filelock around sessions/ read/write)",
  "unblocks": [
    "Multiple Ralph loops in different worktrees",
    "Background constraint scanning while loop runs",
    "Experimental features running in parallel"
  ]
}
```

### Ralph Response

```bash
/ralph:forbid "Running multiple Ralph loops on same project (architectural bottleneck: no file locking on sessions/)"
/ralph:encourage "Add filelock to sessions/ for concurrent multi-worktree support (medium effort, enables features)"
```

### Impact on Degrees of Freedom

**Current limitation**: With single-threaded Stop hook, Claude cannot:
- Run parallel feature experiments
- Have background validation while implementing
- Support concurrent worktree operations

**If architectural bottleneck is unblocked**: Claude gains freedom to:
- Parallelize independent improvements
- Validate while implementing
- Scale to teams with multiple worktrees

---

## Integration: Using All 5 Prompts in a Session

### Workflow Example

**Day 1: Discovery**
```bash
# Morning: Scan for quick wins
/task "Run Explore Agent Prompt #1: Hardcoded Values"
# Finding: 2 hardcoded paths in settings.json (CRITICAL)
# → /ralph:forbid "Refactoring paths until extracted to env vars"

/task "Run Explore Agent Prompt #4: Testing Gaps"
# Finding: Error handler untested (HIGH)
# → /ralph:forbid "Refactoring error handling without tests"
# → /ralph:encourage "Write edge case tests first"
```

**Day 2: Architecture Assessment**
```bash
/task "Run Explore Agent Prompt #2: Tight Coupling"
# Finding: Config schema tightly coupled to template rendering (HIGH)
# → /ralph:forbid "Changing config schema without coordinating template changes"

/task "Run Explore Agent Prompt #5: Architectural Bottlenecks"
# Finding: State management is single-threaded (MEDIUM)
# → /ralph:encourage "Add file locking to sessions/ (enables parallelization)"
```

**Day 3: Knowledge Documentation**
```bash
/task "Run Explore Agent Prompt #3: Undocumented Assumptions"
# Finding: Busywork categories hardcoded but not documented (MEDIUM)
# → /ralph:encourage "Document busywork list in MENTAL-MODEL.md with override instructions"
```

### Forbidden/Encouraged Summary After Discovery

```json
{
  "forbidden": [
    "Refactoring paths (hardcoded /Users/terryli/ in 2 files)",
    "Refactoring error handling without edge case tests",
    "Changing config schema without coordinating template extraction",
    "Running multiple Ralph loops on same project (no file locking)"
  ],
  "encouraged": [
    "Extract hardcoded paths to $HOME environment variable",
    "Write integration tests for file permission/deletion edge cases",
    "Add file locking to sessions/ directory for concurrent support",
    "Document busywork categories in MENTAL-MODEL.md"
  ]
}
```

### Outcome

Instead of Claude exploring blindly and hitting constraints:
- Claude has **clear forbidden zones** (3 high-risk changes)
- Claude has **clear guided improvements** (4 priorities)
- Claude's **degrees of freedom are optimized** for productive work
- **Unexpected failures are prevented** by avoiding forbidden zones

---

## Adding Prompts to Your Project

### Step 1: Identify Your Constraints

Use the 5 Explore prompts to scan YOUR project:

```bash
# For typical project (not alpha-forge):
/task "Scan [your-project] for HARDCODED VALUES using Prompt #1"
/task "Scan [your-project] for TIGHT COUPLING using Prompt #2"
/task "Scan [your-project] for UNDOCUMENTED ASSUMPTIONS using Prompt #3"
/task "Scan [your-project] for TESTING GAPS using Prompt #4"
/task "Scan [your-project] for ARCHITECTURAL BOTTLENECKS using Prompt #5"
```

### Step 2: Create Forbidden/Encouraged Lists

```bash
/ralph:forbid "[from HIGH/CRITICAL findings]"
/ralph:encourage "[constraint resolutions in order of impact]"
```

### Step 3: Run Ralph with Optimized Guidance

```bash
/ralph:start
# Ralph now operates with precise degrees of freedom
# - Forbidden zones prevent breaking changes
# - Encouraged items guide toward high-impact work
```

---

## Related

- **Main Documentation**: [/plugins/ralph/docs/EXPLORE-AGENT-PROMPTS.md](./EXPLORE-AGENT-PROMPTS.md)
- **Task Format**: [/plugins/ralph/docs/EXPLORE-TASK-PROMPTS.txt](./EXPLORE-TASK-PROMPTS.txt)
- **Constraint Scanner**: [/plugins/ralph/scripts/constraint-scanner.py](/plugins/ralph/scripts/constraint-scanner.py)
- **Ralph ADR**: [/docs/adr/2025-12-29-ralph-constraint-scanning.md](/docs/adr/2025-12-29-ralph-constraint-scanning.md)
