---
adr: 2025-12-20-ralph-rssi-eternal-loop
source: ~/.claude/plans/optimized-twirling-river.md
implementation-status: completed
phase: phase-3
last-updated: 2025-12-26
validated: 2025-12-26
---

# Design Spec: Ralph RSSI Eternal Loop Architecture

**ADR**: [Ralph RSSI Eternal Loop Architecture](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)

## Overview

Transform Ralph from idle-prone exploration to true RSSI (Recursively Self-Improving Super Intelligence) with an eternal loop that never stops improving.

## RSSI Maturity Levels

| Level | Name              | Behavior                           | Status      |
| ----- | ----------------- | ---------------------------------- | ----------- |
| 0     | Idle              | Returns empty list, does nothing   | Replaced    |
| 2     | Dynamic Discovery | Scan for available tools, use them | Implemented |
| 3     | History Mining    | Learn from past sessions           | Implemented |
| 4     | Self-Modification | Improve own discovery code         | Implemented |
| 5     | Meta-RSSI         | Improve how it improves            | Implemented |
| 6     | Web Discovery     | Search for domain-aligned features | Implemented |

## Implementation Tasks

### Task 1: Create `ralph_discovery.py` (Level 2) ✅

**File**: `plugins/ralph/hooks/ralph_discovery.py` _(renamed from rssi_discovery.py in v9.3.1)_

- [x] `discover_available_tools()` - Dynamically discover installed tools (ruff, mypy, pylint, bandit, gitleaks, lychee)
- [x] `_discover_mise_tasks()` - Parse mise.toml for available tasks
- [x] `_discover_npm_scripts()` - Parse package.json for available scripts
- [x] `ralph_scan_opportunities()` - Ralph-grade scanning with 7 tiers:
  - Tier 1: Available linters (ruff, mypy)
  - Tier 2: Git-based discovery (uncommitted changes)
  - Tier 3: Code pattern analysis (TODO/FIXME)
  - Tier 4: Project-specific tasks (mise, npm)
  - Tier 5: Security scanning (gitleaks, bandit)
  - Tier 6: Structural analysis (docstrings, READMEs)
  - Tier 7: RSSI meta-improvement (always available)
- [x] `_analyze_codebase_structure()` - Find structural improvement opportunities

### Task 2: Create `ralph_history.py` (Level 3) ✅

**File**: `plugins/ralph/hooks/ralph_history.py` _(renamed from rssi_history.py in v9.3.1)_

- [x] `mine_session_history()` - Analyze past sessions for high-value patterns
- [x] `_extract_work_pattern()` - Extract work type from context lines
- [x] `get_recent_commits_for_analysis()` - Find commits needing follow-up
- [x] `get_session_output_patterns()` - Analyze recent session outputs for patterns

### Task 3: Create `ralph_evolution.py` (Level 4) ✅

**File**: `plugins/ralph/hooks/ralph_evolution.py` _(renamed from rssi_evolution.py in v9.3.1)_

- [x] `load_evolution_state()` - Load persisted evolution state
- [x] `save_evolution_state()` - Persist evolution state to JSON
- [x] `propose_new_check()` - Create proposal for new check
- [x] `track_check_effectiveness()` - Record whether check led to improvement
- [x] `get_prioritized_checks()` - Return checks ordered by effectiveness
- [x] `suggest_capability_expansion()` - Suggest tools to install
- [x] `get_disabled_checks()` - Get list of disabled checks
- [x] `disable_underperforming_check()` - Mark check as disabled
- [x] `learn_project_pattern()` - Record learned project patterns
- [x] `get_learned_patterns()` - Get all learned patterns

### Task 4: Create `ralph_meta.py` (Level 5) ✅

**File**: `plugins/ralph/hooks/ralph_meta.py` _(renamed from rssi_meta.py in v9.3.1)_

- [x] `analyze_discovery_effectiveness()` - Meta-analysis of discovery quality
- [x] `improve_discovery_mechanism()` - Core meta-RSSI: improve discovery itself
  - Strategy 1: Disable underperforming checks
  - Strategy 2: Learn from project structure
  - Strategy 3: Evolve based on repo type
  - Strategy 4: Detect CI/CD patterns
- [x] `get_meta_suggestions()` - Generate meta-level improvement suggestions
- [x] `should_expand_capabilities()` - Determine if should suggest new tools

### Task 5: Create `ralph_web_discovery.py` (Level 6) ✅

**File**: `plugins/ralph/hooks/ralph_web_discovery.py` _(renamed from rssi_web_discovery.py in v9.3.1)_

- [x] `analyze_repo_theme()` - Understand repo's theme, domain, positioning
- [x] `generate_web_search_queries()` - Generate search queries based on theme
- [x] `web_search_for_ideas()` - Generate prompts for WebSearch tool
- [x] `generate_quality_search_queries()` - SOTA-focused searches
- [x] `evaluate_solution_quality()` - Verify SOTA/well-maintained criteria
- [x] `get_sota_alternatives()` - Return legacy to SOTA mapping
- [x] `get_quality_gate_instructions()` - Return quality gate instructions for template

### Task 6: Create `ralph_knowledge.py` (State Persistence) ✅

**File**: `plugins/ralph/hooks/ralph_knowledge.py` _(renamed from rssi_knowledge.py in v9.3.1)_

- [x] `RalphKnowledge` dataclass with fields:
  - Level 3: `commit_patterns`, `effective_checks`
  - Level 4: `disabled_checks`, `proposed_checks`, `learned_conventions`
  - Level 5: `overall_effectiveness`, `improvement_history`
  - Level 6: `domain_insights`, `sota_standards`, `feature_ideas`
- [x] `persist()` - Save to `~/.claude/automation/loop-orchestrator/state/ralph-knowledge.json`
- [x] `load()` - Load accumulated knowledge from previous sessions
- [x] `add_patterns()` - Add learned patterns from history mining
- [x] `apply_improvements()` - Record improvements made
- [x] `evolve()` - Apply meta-analysis results
- [x] `add_feature_idea()` - Add feature idea from web discovery
- [x] `add_sota_standard()` - Record SOTA standard for domain
- [x] `increment_iteration()` - Increment and return iteration count
- [x] `get_summary()` - Get summary for template rendering

### Task 7: Update `discovery.py` ✅

**File**: `plugins/ralph/hooks/discovery.py`

- [x] Import `ralph_scan_opportunities` from `ralph_discovery.py`
- [x] Replace `scan_work_opportunities()` with Ralph version
- [x] Orchestrate all Ralph modules in sequence
- [x] Add `get_ralph_exploration_context()` for full template context

### Task 8: Create Unified Ralph Template ✅

**File**: `plugins/ralph/hooks/templates/ralph-unified.md` _(renamed from rssi-unified.md in v9.3.1)_

> **Note**: Originally named `exploration-mode.md`, consolidated with `implementation-mode.md` into unified template.

- [x] Add RSSI Protocol header
- [x] Add AUTONOMOUS MODE section
- [x] Add USER GUIDANCE section (encouraged/forbidden) - **works in ALL phases**
- [x] Add CURRENT PHASE section with `{% if task_complete %}` conditional
- [x] Add IMPLEMENTATION phase content (todos, completion markers)
- [x] Add EXPLORATION phase content (OODA loop, discovery)
- [x] Add CONSTRAINTS section
- [x] Add ITERATION STATUS with web research trigger (exploration only)
- [x] Add "NEVER idle" directive

### Task 9: Update `loop-until-done.py` ✅

**File**: `plugins/ralph/hooks/loop-until-done.py`

- [x] Integrate RSSI modules into continuation prompt
- [x] Pass accumulated knowledge to template
- [x] Track RSSI iteration count
- [x] Ensure eternal loop behavior in exploration mode

### Task 10: Update `template_loader.py` ✅

**File**: `plugins/ralph/hooks/template_loader.py`

- [x] Add `render_unified()` method as single entry point (v8.7.0+)
- [x] Pass `task_complete` flag to toggle implementation/exploration content
- [x] User guidance always loaded regardless of phase
- [x] `render_exploration()` now delegates to `render_unified(task_complete=True)`

## Quality Gate

All solutions must meet one of:

### Custom Code

- SOTA concepts (rapidfuzz, structlog, modern Python 3.11+)
- Async where beneficial (asyncio, httpx)

### OSS Dependencies

- Recently updated (last commit within 6 months)
- Highly active (regular releases)
- Well-maintained (good docs, tests, community)

## Success Criteria

- [x] Level 2: Dynamic tool discovery works
- [x] Level 3: History mining finds patterns
- [x] Level 4: Self-modification tracks effectiveness
- [x] Level 5: Meta-improvement analyzes discovery
- [x] Level 6: Web search finds feature ideas
- [x] Quality Gate: All solutions verified SOTA
- [x] `ralph_scan_opportunities()` NEVER returns empty
- [x] Template enforces "always act" behavior
- [x] Ralph actively explores with web search
- [x] Eternal loop never idles

## Files Created

| File                                         | Purpose                    |
| -------------------------------------------- | -------------------------- |
| `plugins/ralph/hooks/ralph_discovery.py`     | Level 2: Dynamic discovery |
| `plugins/ralph/hooks/ralph_history.py`       | Level 3: History mining    |
| `plugins/ralph/hooks/ralph_evolution.py`     | Level 4: Self-modification |
| `plugins/ralph/hooks/ralph_meta.py`          | Level 5: Meta-improvement  |
| `plugins/ralph/hooks/ralph_web_discovery.py` | Level 6: Web search        |
| `plugins/ralph/hooks/ralph_knowledge.py`     | State persistence          |

> **v9.3.1**: All files renamed from `rssi_*.py` to `ralph_*.py` for consistency.

## Files Modified

| File                                             | Change                                      |
| ------------------------------------------------ | ------------------------------------------- |
| `plugins/ralph/hooks/discovery.py`               | Orchestrate Ralph modules                   |
| `plugins/ralph/hooks/templates/ralph-unified.md` | Unified Ralph template (replaces dual arch) |
| `plugins/ralph/hooks/loop-until-done.py`         | Integrate eternal loop, single code path    |
| `plugins/ralph/hooks/template_loader.py`         | Add `render_unified()` method               |

> **v8.7.0**: Consolidated `implementation-mode.md` and `exploration-mode.md` into single template.
> **v9.3.1**: Renamed template from `rssi-unified.md` to `ralph-unified.md`.

## Bug Fix: Cross-Directory Stop (v7.16.0+)

**Issue**: `/ralph:stop` wrote state to wrong project when invoked from different directory.

**Root Cause**: `stop.md` fell back to `$(pwd)` instead of session's `CLAUDE_PROJECT_DIR`.

### Fix Components

- [x] `stop.md`: 4-method holistic resolution (session-state, holistic, parent-walk, global-stop)
- [x] `loop-until-done.py`: Add `project_path` field to session state
- [x] `loop-until-done.py`: Check global stop signal FIRST (version-agnostic)
- [x] `core/constants.py`: Centralize magic numbers (PLR2004 compliance)

### Verification (2025-12-25)

| Check                         | Status | Evidence                                       |
| ----------------------------- | ------ | ---------------------------------------------- |
| stop.md has 4 methods         | ✅     | `grep -c "Method [1-4]:" → 4`                  |
| project_path in default_state | ✅     | Line 412: `"project_path": ""`                 |
| Global stop signal check      | ✅     | Lines 363-380: checks `ralph-global-stop.json` |
| Observability logging         | ✅     | Lines 357, 377, 385, 395, 404, 451             |
| E2E cross-directory test      | ✅     | Global stop prevents hook continuation         |
| Unit tests pass               | ✅     | 3/3 tests pass (0.23s)                         |
| PLR2004 production code       | ✅     | 0 violations (was 27+)                         |
