---
adr: 2025-12-20-ralph-rssi-eternal-loop
source: ~/.claude/plans/optimized-twirling-river.md
implementation-status: in_progress
phase: phase-1
last-updated: 2025-12-20
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

### Task 1: Create `rssi_discovery.py` (Level 2) ✅

**File**: `plugins/ralph/hooks/rssi_discovery.py`

- [x] `discover_available_tools()` - Dynamically discover installed tools (ruff, mypy, pylint, bandit, gitleaks, lychee)
- [x] `_discover_mise_tasks()` - Parse mise.toml for available tasks
- [x] `_discover_npm_scripts()` - Parse package.json for available scripts
- [x] `rssi_scan_opportunities()` - RSSI-grade scanning with 7 tiers:
  - Tier 1: Available linters (ruff, mypy)
  - Tier 2: Git-based discovery (uncommitted changes)
  - Tier 3: Code pattern analysis (TODO/FIXME)
  - Tier 4: Project-specific tasks (mise, npm)
  - Tier 5: Security scanning (gitleaks, bandit)
  - Tier 6: Structural analysis (docstrings, READMEs)
  - Tier 7: RSSI meta-improvement (always available)
- [x] `_analyze_codebase_structure()` - Find structural improvement opportunities

### Task 2: Create `rssi_history.py` (Level 3) ✅

**File**: `plugins/ralph/hooks/rssi_history.py`

- [x] `mine_session_history()` - Analyze past sessions for high-value patterns
- [x] `_extract_work_pattern()` - Extract work type from context lines
- [x] `get_recent_commits_for_analysis()` - Find commits needing follow-up
- [x] `get_session_output_patterns()` - Analyze recent session outputs for patterns

### Task 3: Create `rssi_evolution.py` (Level 4) ✅

**File**: `plugins/ralph/hooks/rssi_evolution.py`

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

### Task 4: Create `rssi_meta.py` (Level 5) ✅

**File**: `plugins/ralph/hooks/rssi_meta.py`

- [x] `analyze_discovery_effectiveness()` - Meta-analysis of discovery quality
- [x] `improve_discovery_mechanism()` - Core meta-RSSI: improve discovery itself
  - Strategy 1: Disable underperforming checks
  - Strategy 2: Learn from project structure
  - Strategy 3: Evolve based on repo type
  - Strategy 4: Detect CI/CD patterns
- [x] `get_meta_suggestions()` - Generate meta-level improvement suggestions
- [x] `should_expand_capabilities()` - Determine if should suggest new tools

### Task 5: Create `rssi_web_discovery.py` (Level 6) ✅

**File**: `plugins/ralph/hooks/rssi_web_discovery.py`

- [x] `analyze_repo_theme()` - Understand repo's theme, domain, positioning
- [x] `generate_web_search_queries()` - Generate search queries based on theme
- [x] `web_search_for_ideas()` - Generate prompts for WebSearch tool
- [x] `generate_quality_search_queries()` - SOTA-focused searches
- [x] `evaluate_solution_quality()` - Verify SOTA/well-maintained criteria
- [x] `get_sota_alternatives()` - Return legacy to SOTA mapping
- [x] `get_quality_gate_instructions()` - Return quality gate instructions for template

### Task 6: Create `rssi_knowledge.py` (State Persistence) ✅

**File**: `plugins/ralph/hooks/rssi_knowledge.py`

- [x] `RSSIKnowledge` dataclass with fields:
  - Level 3: `commit_patterns`, `effective_checks`
  - Level 4: `disabled_checks`, `proposed_checks`, `learned_conventions`
  - Level 5: `overall_effectiveness`, `improvement_history`
  - Level 6: `domain_insights`, `sota_standards`, `feature_ideas`
- [x] `persist()` - Save to `~/.claude/automation/loop-orchestrator/state/rssi-knowledge.json`
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

- [x] Import `rssi_scan_opportunities` from `rssi_discovery.py`
- [x] Replace `scan_work_opportunities()` with RSSI version
- [x] Orchestrate all RSSI modules in sequence
- [x] Add `get_rssi_exploration_context()` for full template context

### Task 8: Update `exploration-mode.md` Template ✅

**File**: `plugins/ralph/hooks/templates/exploration-mode.md`

- [x] Add RSSI ETERNAL LOOP header with iteration count
- [x] Add DISCOVERED OPPORTUNITIES section (never hidden)
- [x] Add RSSI PROTOCOL with 5-step order
- [x] Add WEB DISCOVERY section with search queries
- [x] Add QUALITY GATE section (SOTA/OSS checks)
- [x] Add CAPABILITY EXPANSION section
- [x] Add "NEVER idle" directive
- [x] Add ACCUMULATED FEATURE IDEAS section

### Task 9: Update `loop-until-done.py` ✅

**File**: `plugins/ralph/hooks/loop-until-done.py`

- [x] Integrate RSSI modules into continuation prompt
- [x] Pass accumulated knowledge to template
- [x] Track RSSI iteration count
- [x] Ensure eternal loop behavior in exploration mode

### Task 10: Update `template_loader.py` ✅

**File**: `plugins/ralph/hooks/template_loader.py`

- [x] Update `render_exploration()` to accept full RSSI context
- [x] Pass all RSSI template variables to Jinja2 renderer

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
- [x] `rssi_scan_opportunities()` NEVER returns empty
- [x] Template enforces "always act" behavior
- [x] Ralph actively explores with web search
- [x] Eternal loop never idles

## Files to Create

| File                                        | Purpose                    |
| ------------------------------------------- | -------------------------- |
| `plugins/ralph/hooks/rssi_discovery.py`     | Level 2: Dynamic discovery |
| `plugins/ralph/hooks/rssi_history.py`       | Level 3: History mining    |
| `plugins/ralph/hooks/rssi_evolution.py`     | Level 4: Self-modification |
| `plugins/ralph/hooks/rssi_meta.py`          | Level 5: Meta-improvement  |
| `plugins/ralph/hooks/rssi_web_discovery.py` | Level 6: Web search        |
| `plugins/ralph/hooks/rssi_knowledge.py`     | State persistence          |

## Files to Modify

| File                                                | Change                   |
| --------------------------------------------------- | ------------------------ |
| `plugins/ralph/hooks/discovery.py`                  | Orchestrate RSSI modules |
| `plugins/ralph/hooks/templates/exploration-mode.md` | Full RSSI template       |
| `plugins/ralph/hooks/loop-until-done.py`            | Integrate eternal loop   |
