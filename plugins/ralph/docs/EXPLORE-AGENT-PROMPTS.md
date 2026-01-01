# Ralph Explore Agent Prompts
## Discovering Constraints on Claude's Degrees of Freedom

> **Purpose**: These 5 specialized Explore agent prompts discover environment, architectural, and convention-based constraints that limit Claude's autonomy during Ralph loops. Each focuses on one category of constraint and returns structured findings suitable for the forbidden/encouraged AUQ.

> **Usage**: Copy each prompt into the Task tool (`/task` command or equivalent) to run autonomous sub-agent searches. Results feed directly into `ralph-config.json` guidance arrays and constraint-scanner.py pattern detection.

---

## 1. Hardcoded Values & Magic Numbers Scanner

**Category**: Structural constraints that block refactoring and feature exploration

**What it finds**:
- Absolute file paths that break across environments
- Hardcoded version strings, configuration values, thresholds
- Magic numbers without explanation or parameterization
- Environment-specific settings embedded in code

**Why it matters**: When paths/values are hardcoded, Claude cannot safely refactor architecture, test variations, or explore alternative implementations without breaking things. Each hardcoded value reduces degrees of freedom.

```
SCAN FOR HARDCODED CONSTRAINTS

Target: Find values, paths, and magic numbers that limit Claude's refactoring freedom.

Search Strategy:
1. Absolute paths: Search all .py, .toml, .json, .yaml files for patterns:
   - /Users/[username]/
   - /home/[username]/
   - Explicit home directory expansions (~/ without variable)
   - Environment-specific mount points (/mnt/data, /media/data)
   Report: file, line, value, severity (CRITICAL if current user path)

2. Version/threshold magic numbers: Search for patterns:
   - Numbers not in constants: min_sharpe=1.5, threshold=0.75, timeout=30
   - Array indices without named constants: data[2], config[0]
   - Percentage/ratio literals: * 100, / 1000, > 0.95
   Report: file, line, context (3 lines), recommendation to parameterize

3. Configuration hardcoding: Search for patterns in code that reads from:
   - Fixed config paths (e.g., 'config.json' string literal, not from env)
   - Project structure assumptions (e.g., '../../../data' relative imports)
   Report: file, dependencies on fixed structure, alternative suggestions

Output Format:
{
  "constraint_type": "hardcoded_value",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "file": "path/to/file:line",
  "value": "actual value found",
  "category": "path|version|threshold|config",
  "impact": "Prevents Claude from: [refactoring / testing variations / exploring alternatives]",
  "recommendation": "Extract to [environment variable / configuration file / named constant]"
}

Deep Dive: If found, check if any tests mock or override these values. If not, constraint is higher severity (no way to test alternatives).
```

---

## 2. Tightly Coupled Components & Dependency Risks

**Category**: Architectural constraints that create cascading failure risks

**What it finds**:
- Components with hidden dependencies (not declared in imports)
- File ordering assumptions (this script must run before that one)
- State assumptions (requires database in specific schema state)
- Rigid data flow pipelines that cannot be reordered or parallelized

**Why it matters**: When components are tightly coupled, Claude cannot safely refactor one without understanding all its dependents. This creates invisible risk that blocks exploration.

```
SCAN FOR COUPLING CONSTRAINTS

Target: Find architectural rigidity that blocks safe refactoring and parallel exploration.

Search Strategy:
1. Import/dependency analysis:
   - List all .py files and their imports
   - Identify circular imports: A imports B, B imports A
   - Find files with >10 imports (high coupling indicator)
   - Find imports of private modules (underscore-prefixed)
   Report: file pair, type of coupling (circular/heavy/private)

2. Global state & side effects:
   - Search for global variables, singletons, class variables
   - Identify functions with side effects (file writes, config mutations, env changes)
   - Find code paths that depend on execution order (e.g., setup() must run first)
   Report: location, what state is modified, what depends on it

3. Data schema assumptions:
   - In dataclass/Pydantic models, find required fields with no defaults
   - In database code, find assumptions about schema (e.g., 'users.id is PRIMARY KEY')
   - In config loading, find code that assumes specific structure
   Report: location, assumption, alternative structures explored or documented

4. Pipeline ordering constraints:
   - Find shell scripts, Makefiles, or orchestration that enforces strict ordering
   - Identify comments like "MUST run after X", "depends on output of Y"
   Report: script, ordering constraints, flexibility assessment

Output Format:
{
  "constraint_type": "tight_coupling",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "components": ["component_A", "component_B"],
  "coupling_type": "circular_import|heavy_dependency|global_state|pipeline_order|schema_assumption",
  "location": "file1:line or file1 <-> file2",
  "risk": "Changing component_A will break: [list of affected components]",
  "degrees_of_freedom_blocked": "Cannot [parallelize / reorder / refactor independently / test in isolation]",
  "recommendation": "Decouple via [dependency injection / config parameter / abstract interface]"
}

Critical: Check if test suite tests components in isolation. If not, coupling is risky.
```

---

## 3. Undocumented Assumptions & Implicit Conventions

**Category**: Knowledge constraints where "how it works" is tribal knowledge, not written down

**What it finds**:
- Implicit assumptions in code comments (e.g., "assumes data is already sorted")
- Naming conventions with special meaning (prefixes/suffixes)
- Undocumented data format contracts
- Silent failure modes (code that fails gracefully without error)

**Why it matters**: Claude works from documentation. When assumptions are undocumented, Claude must either guess (and fail) or spend time reverse-engineering. This burns iteration budget.

```
SCAN FOR IMPLICIT ASSUMPTIONS

Target: Find undocumented knowledge that limits Claude's autonomy and causes surprises.

Search Strategy:
1. Comments vs code gap:
   - Find functions/classes with no docstring
   - Find code blocks with cryptic variable names (x, tmp, data1, data2)
   - Find comments that say "This is weird because..." or "Don't change X or..."
   Report: location, assumption extracted from comment, whether it's in docstring/README

2. Naming conventions with hidden meaning:
   - Find prefixes/suffixes used consistently (e.g., _internal, tmp_, cached_, v1_)
   - Search for test names that imply behavior (test_handles_edge_case, test_slow)
   - Find class names ending in 'Base', 'Impl', 'Mixin'
   Report: pattern, what it means, whether documented

3. Data format contracts:
   - Find JSON/YAML parsing code that assumes specific structure
   - Find CSV processing that assumes column order
   - Find API clients that assume response schema
   Report: location, assumed schema, whether validation exists

4. Silent failures & error suppression:
   - Find try/except blocks that catch Exception broadly
   - Find functions that return None/empty on error without logging
   - Find assertions that silently fail in production
   Report: location, what error is suppressed, impact of silence

5. Conditional logic without obvious reason:
   - Find if/else branches with no explanation
   - Find feature flags without documentation
   - Find version-specific handling (if version > X: do this)
   Report: location, condition, why it exists

Output Format:
{
  "constraint_type": "undocumented_assumption",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "location": "file:line or section",
  "assumption": "Brief statement of what's assumed",
  "consequence_if_violated": "What breaks if assumption is wrong",
  "discovery_method": "Found by [code inspection / comment reading / reverse engineering]",
  "is_documented": true|false,
  "recommendation": "Document in [docstring / README / ADR / inline comment]"
}

Critical: If assumption blocks multiple parts of codebase, severity is higher.
```

---

## 4. Testing Gaps & Risky Modification Zones

**Category**: Robustness constraints where code quality prevents safe changes

**What it finds**:
- Functions/modules with zero test coverage
- Edge cases mentioned in comments but not tested
- Untested code paths (error handlers, rare conditions)
- Tests that pass but don't validate behavior (mock everything)

**Why it matters**: When code lacks tests, Claude must either: (a) write tests before changing anything, or (b) change carefully with high risk. Either way, degrees of freedom shrink because changes require extra caution.

```
SCAN FOR TESTING GAPS

Target: Find code regions where modifications are risky due to insufficient validation.

Search Strategy:
1. Coverage gaps:
   - Compare source file tree (.py, .ts, .go, etc.) to test file tree
   - Identify files with no corresponding test file
   - Identify utility/helper modules never imported by tests
   Report: file, test coverage status (none/partial/good), imports-by-tests count

2. Untested code paths:
   - In error handlers (except blocks), check if tests exercise them
   - In conditional branches, check if all branches are tested
   - In CLI argument parsing, check if all paths are tested
   Report: location, code path, whether tested, impact if broken

3. Edge cases & boundary conditions:
   - Find comments mentioning "edge case", "TODO: test", "known issue"
   - Find numeric boundaries (0, negative, infinity, empty)
   - Find list/dict operations on empty collections
   Report: location, edge case, whether it's tested

4. Mock-heavy tests:
   - Find test files that mock all dependencies (tests verify mock calls, not behavior)
   - Find tests with >70% mock percentage
   - Find tests that don't assert on actual output
   Report: test file, mock percentage, what's actually verified

5. Integration points:
   - Find where code calls external services (APIs, databases, file I/O)
   - Check if these calls are tested with real vs mocked versions
   - Find integration tests (if any) and coverage
   Report: integration point, test approach (real/mock/none), risk level

Output Format:
{
  "constraint_type": "testing_gap",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "location": "file or function",
  "gap_type": "no_tests|edge_cases|untested_paths|mock_heavy|integration_untested",
  "test_coverage": "percentage|unknown",
  "risk_if_modified": "Changing this could break: [behavior without detection]",
  "blocks_refactoring_of": "[list of potential improvements that require test coverage first]",
  "recommendation": "Add tests for: [specific scenarios]"
}

Critical: If a change would break production with no way to know beforehand, severity is CRITICAL.
```

---

## 5. Architectural Bottlenecks & Rigid Structures

**Category**: Design constraints where the codebase structure itself prevents certain kinds of work

**What it finds**:
- Monolithic services that cannot be parallelized
- Layer violations (UI code calling database directly)
- Missing abstractions that prevent plugin/extension architecture
- State machines that assume linear progression (cannot backtrack/retry)

**Why it matters**: Some architectural decisions lock Claude into specific approaches. For example, if backtest results must be sequential, Claude cannot parallelize feature engineering. This removes entire categories of improvements.

```
SCAN FOR ARCHITECTURAL BOTTLENECKS

Target: Find structural limitations that prevent categories of improvements (e.g., parallelization, modularization, extensibility).

Search Strategy:
1. Monolithic vs modular assessment:
   - Identify the "largest" component (most lines, most dependencies)
   - Check if it can be split into independent modules
   - Check for feature flags or plugin systems (if none, architecture is rigid)
   Report: component, size, dependencies, modularity potential

2. Layer violations:
   - Map architecture (UI / Logic / Data layers expected)
   - Find cross-layer imports that skip layers (UI directly accessing database)
   - Find data access code in business logic
   Report: violation location, expected vs actual layers, impact

3. Single points of failure:
   - Identify components with zero redundancy
   - Find classes/functions everything depends on
   - Find places where "if this goes down, system fails"
   Report: component, failure scenario, redundancy options

4. Parallelization barriers:
   - Find sequential loops that could be parallel
   - Check for shared mutable state that prevents parallelization
   - Find code that assumes order (e.g., "step 1 then step 2")
   Report: location, sequence, parallelization potential, barriers to it

5. Extensibility assessment:
   - Check if you can add features without modifying existing code
   - Look for plugin systems, registry patterns, or strategy patterns
   - Find hardcoded behavior that should be configurable
   Report: area, current extensibility, extension points available

Output Format:
{
  "constraint_type": "architectural_bottleneck",
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "bottleneck_type": "monolithic|layer_violation|single_point_of_failure|parallelization_barrier|low_extensibility",
  "location": "component or file",
  "current_design": "What the architecture does",
  "classes_of_improvements_blocked": ["parallelization", "feature modularization", "alternative algorithms"],
  "architectural_pattern": "Current: [pattern]. Alternative: [pattern that would unblock]",
  "estimated_effort_to_unblock": "low|medium|high",
  "recommendation": "Refactor to [pattern] to enable [blocked improvements]"
}

Deep Dive: For each bottleneck, assess: is this a fundamental design choice (immutable) or implementation choice (refactorable)?
```

---

## Usage in Ralph Loop

### Integration Points

These prompts feed Claude's autonomy in two ways:

#### 1. **Forbidden List** (what to avoid)
Results with `severity: CRITICAL|HIGH` become items in `/ralph:forbid`:
```bash
/ralph:forbid "Refactoring /Users/terry/ paths (hardcoded home directory)"
/ralph:forbid "Adding tests without docs (8 functions untested, need design first)"
```

#### 2. **Encouraged List** (what to prioritize)
Once a constraint is identified, encouraging its resolution:
```bash
/ralph:encourage "Extract environment paths to .env (2 hardcoded paths found)"
/ralph:encourage "Write integration tests (API mocking insufficient)"
```

### Phase Integration

| Phase | Usage |
|-------|-------|
| **OBSERVE** | Run Explore prompts #1-5 to scan project |
| **ORIENT** | Categorize findings by severity, map to blocked improvements |
| **DECIDE** | For each discovery, decide: tackle now or defer? |
| **ACT** | Use guidance lists to execute high-confidence improvements |

### AUQ Pre-Selection

The `constraint-scanner.py` output can pre-populate the AUQ:

```python
# In start.md AUQ handler:
critical_constraints = [c for c in scan_result if c.severity == "CRITICAL"]
for constraint in critical_constraints:
    forbidden_candidates.append(constraint.description)
```

---

## Example Workflow

### Session 1: Discover
```bash
/task "Run Explore Agent Prompt #1: Hardcoded Values Scanner"
# Returns: 3 CRITICAL (hardcoded paths), 2 HIGH (magic numbers)

/task "Run Explore Agent Prompt #4: Testing Gaps Scanner"
# Returns: 8 untested edge cases, 1 integration point with no tests
```

### Session 2: Forbid & Encourage
```bash
/ralph:forbid "Refactoring file paths (5 hardcoded paths found)"
/ralph:forbid "Modifying error handlers (untested code paths)"
/ralph:encourage "Extract hardcoded paths to environment variables"
/ralph:encourage "Write integration tests for API layer"
```

### Session 3: Execute
Ralph now operates with precise guidance:
- Claude avoids forbidden zones
- Claude prioritizes encouraged improvements
- Degrees of freedom are optimized (high-risk work forbidden, high-impact work encouraged)

---

## Metrics & Feedback Loop

Track constraint discovery effectiveness:

```json
{
  "session": "2025-12-31T10:00:00Z",
  "constraints_found": {
    "hardcoded_values": 3,
    "tight_coupling": 2,
    "undocumented_assumptions": 5,
    "testing_gaps": 8,
    "architectural_bottlenecks": 1
  },
  "forbidden_items_created": 5,
  "encouraged_items_created": 4,
  "degrees_of_freedom_improved": true,
  "unexpected_failures_blocked": 2
}
```

After each Ralph session, review:
- Did forbidden items prevent breaking changes? ✓
- Did encouraged items guide toward high-impact work? ✓
- Were there constraints discovered mid-session? (update prompts)

---

## Related

- **ADR**: [/docs/adr/2025-12-29-ralph-constraint-scanning.md](/docs/adr/2025-12-29-ralph-constraint-scanning.md)
- **Scanner**: [/plugins/ralph/scripts/constraint-scanner.py](/plugins/ralph/scripts/constraint-scanner.py)
- **Config Schema**: [/plugins/ralph/hooks/core/config_schema.py](/plugins/ralph/hooks/core/config_schema.py)
- **Ralph Mental Model**: [/plugins/ralph/MENTAL-MODEL.md](/plugins/ralph/MENTAL-MODEL.md#constraint-scanner-v300)
