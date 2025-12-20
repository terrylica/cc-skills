# Ralph Plugin for Claude Code

Keep Claude Code working autonomously until tasks are complete - implements the Ralph Wiggum technique as Claude Code hooks with **RSSI** (Recursively Self-Improving Super Intelligence) capabilities.

## What This Plugin Does

This plugin adds autonomous loop mode to Claude Code through 5 commands and 2 hooks:

**Commands:**

- `/ralph:start` - Enable loop mode (Claude continues working)
- `/ralph:stop` - Disable loop mode immediately
- `/ralph:status` - Show current loop state and metrics
- `/ralph:config` - View/modify runtime limits
- `/ralph:hooks` - Install/uninstall hooks to settings.json

**Hooks:**

- **Stop hook** (`loop-until-done.py`) - RSSI-enhanced autonomous operation
- **PreToolUse hook** (`archive-plan.sh`) - Archives `.claude/plans/*.md` files before overwrite

## Quick Start

```bash
# 1. Install hooks
/ralph:hooks install

# 2. Restart Claude Code (hooks load at startup)

# 3. Start the loop
/ralph:start

# Claude will now continue working until:
# - Task completion detected (multi-signal, see below)
# - Validation exhausted (score >= 0.8)
# - Maximum time/iterations reached
# - You run /ralph:stop
```

## How It Works

### Mode Progression (RSSI Workflow)

```
IMPLEMENTATION (working on checklist)
       ↓
   [task_complete = True]
       ↓
VALIDATION (3 rounds, multi-perspective)
   Round 1: Static analysis (parallel sub-agents)
   Round 2: Semantic verification (sequential)
   Round 3: Consistency audit (parallel)
       ↓
   [validation_exhausted = True]
       ↓
EXPLORATION (discovery + self-improvement)
       ↓
ALLOW STOP (all conditions met)
```

### Multi-Signal Completion Detection

Ralph detects task completion through multiple signals (not just explicit markers):

| Signal                 | Confidence | Description                                |
| ---------------------- | ---------- | ------------------------------------------ |
| Explicit marker        | 1.0        | `[x] TASK_COMPLETE` in file                |
| Frontmatter status     | 0.95       | `implementation-status: completed`         |
| All checkboxes checked | 0.9        | No `[ ]` remaining, has `[x]`              |
| No pending items       | 0.85       | Has checked items, none unchecked          |
| Semantic phrases       | 0.7        | Contains "task complete", "all done", etc. |

Completion triggers when confidence >= 0.7 (configurable).

### Validation Phase (3 Rounds)

After task completion, Ralph runs multi-perspective validation before exploration:

**Round 1 - Static Analysis (Parallel)**

- Linter agent (Ruff: BLE, S110, E722 violations)
- Link validator (lychee: broken markdown links)
- Secret scanner (hardcoded credentials)

**Round 2 - Semantic Verification (Sequential)**

- Reviews Round 1 findings
- Verifies fixes were applied
- Checks for regressions

**Round 3 - Consistency Audit (Parallel)**

- Doc-code alignment check
- Test coverage gap analysis

Validation exhausts when score >= 0.8 or max 3 iterations.

### Exploration/Discovery Mode

After validation, if minimum time/iterations not met:

- Scans for work opportunities (broken links, missing READMEs)
- Provides sub-agent spawning instructions
- Tracks doc ↔ feature alignment

### File Discovery Cascade

Ralph automatically discovers task files using a priority cascade:

1. **Transcript parsing** - Files accessed via Write/Edit/Read to `.claude/plans/`
2. **ITP design specs** - Files with `implementation-status: in_progress` frontmatter
3. **ITP ADRs** - Files with `status: accepted` frontmatter
4. **Local plans** - Newest `.md` in project's `.claude/plans/`
5. **Global plans** - Content-matched or newest in `~/.claude/plans/`

Or specify explicitly: `/ralph:start -f path/to/task.md`

### Safety Features

**Loop Detection**: Stops if outputs are >90% similar across 5 iterations (avoids infinite loops).

**Kill Switch**: Create `.claude/STOP_LOOP` in project root for immediate termination:

```bash
touch .claude/STOP_LOOP  # Emergency stop
```

### Configuration

- **Project-level**: `.claude/loop-config.json`
- **Global defaults**: `~/.claude/automation/loop-orchestrator/config/loop_config.json`
- **POC mode**: `--poc` flag (10 min, 20 iterations, 30s validation timeout)

**Config options**:

```json
{
  "min_hours": 4,
  "max_hours": 9,
  "min_iterations": 50,
  "max_iterations": 99,
  "enable_validation_phase": true,
  "validation_timeout_poc": 30,
  "validation_timeout_normal": 120
}
```

## Files

```
ralph/
├── README.md                   # This file
├── commands/                   # Slash commands
│   ├── start.md
│   ├── stop.md
│   ├── status.md
│   ├── config.md
│   └── hooks.md
├── hooks/                      # Hook implementations (modular)
│   ├── hooks.json              # Hook registration
│   ├── loop-until-done.py      # Stop hook (main orchestrator)
│   ├── completion.py           # Multi-signal completion detection
│   ├── validation.py           # 3-round validation phase
│   ├── discovery.py            # File discovery & work scanning
│   ├── utils.py                # Time tracking, loop detection
│   ├── template_loader.py      # Jinja2 template rendering
│   ├── archive-plan.sh         # PreToolUse hook
│   └── templates/              # Prompt templates (Jinja2 markdown)
│       ├── validation-round-1.md
│       ├── validation-round-2.md
│       ├── validation-round-3.md
│       ├── exploration-mode.md
│       ├── implementation-mode.md
│       └── status-header.md
└── scripts/
    └── manage-hooks.sh         # Hook installation script
```

## Dependencies

**Python** (PEP 723 inline dependencies in loop-until-done.py):

- `rapidfuzz>=3.0.0,<4.0.0` - Fuzzy string matching for loop detection
- `jinja2>=3.1.0,<4.0.0` - Template rendering for prompts

**System tools** (auto-installed via mise/brew if missing):

- `jq` - JSON processing for archive-plan.sh

## Testing

The RSSI implementation includes a comprehensive test suite:

```bash
# Run all tests
cd plugins/ralph/hooks
uv run tests/run_all_tests.py

# Run individual test files
uv run tests/test_completion.py    # Multi-signal completion detection
uv run tests/test_validation.py    # 3-round validation phase
uv run tests/test_utils.py         # Loop detection, time tracking
uv run tests/test_integration.py   # Full workflow simulation

# Run POC validation task
/ralph:start -f plugins/ralph/hooks/tests/poc-task.md --poc
```

**Test Coverage**:

| Module        | Tests                                                   |
| ------------- | ------------------------------------------------------- |
| completion.py | Explicit markers, checkboxes, frontmatter, RSSI signals |
| validation.py | Score computation, exhaustion detection, aggregation    |
| utils.py      | Elapsed hours, loop detection, section extraction       |
| integration   | Mode transitions, file discovery, workflow simulation   |

## Related

- [Geoffrey Huntley's Article](https://ghuntley.com/ralph/) - Original technique
