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

0. **Plan mode system-reminder** - When Claude Code is in plan mode, the assigned plan file
1. **Transcript parsing** - Files accessed via Write/Edit/Read to `.claude/plans/`
2. **ITP design specs** - Files with `implementation-status: in_progress` frontmatter
3. **ITP ADRs** - Files with `status: accepted` frontmatter
4. **Local plans** - Newest `.md` in project's `.claude/plans/`
5. **Global plans** - Content-matched or newest in `~/.claude/plans/`

**Options**:

- Specify explicitly: `/ralph:start -f path/to/task.md`
- Run without focus: `/ralph:start --no-focus` (100% autonomous, no plan tracking)

### Focus File Confirmation

When starting Ralph, you'll be asked to confirm the focus file:

```
Which focus mode for this Ralph session?
○ Use discovered file    → [path to discovered file]
○ Specify different file → You'll provide a custom path
○ Run without focus      → 100% autonomous, no plan tracking
```

The `--no-focus` option is useful for:

- Pure exploration/discovery tasks
- When you want Ralph to work without tracking a specific plan
- Tasks that don't have a corresponding plan file

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

### Multi-Repository Adapter Architecture

Ralph supports project-specific convergence detection via adapters. Each adapter provides:

- **Detection**: Identifies project type from directory structure
- **Metrics reading**: Extracts metrics from existing outputs (no target repo changes)
- **Convergence logic**: Project-specific stopping conditions

**Built-in Adapters**:

| Adapter       | Detection                               | Convergence Signals                                      |
| ------------- | --------------------------------------- | -------------------------------------------------------- |
| `alpha-forge` | `pyproject.toml` contains "alpha-forge" | WFE threshold, diminishing returns, patience, hard limit |
| `universal`   | Fallback (all projects)                 | Defers to RSSI completion detection                      |

**Confidence-Based Decisions**:

Adapters return confidence levels that determine RSSI interaction:

- `0.0`: No opinion, defer to RSSI (default behavior)
- `0.5`: Suggest stop, requires RSSI agreement
- `1.0`: Override RSSI (hard limits like budget exhaustion)

**Session State Isolation**:

Sessions are isolated per project path using hashes:

```
sessions/{session_id}@{path_hash}.json
```

This enables safe operation across git worktrees with the same session ID.

### Adding New Adapters

Create a new adapter in `hooks/adapters/`:

```python
# hooks/adapters/my_project.py
from pathlib import Path
from core.protocols import ProjectAdapter, MetricsEntry, ConvergenceResult

class MyProjectAdapter(ProjectAdapter):
    name = "my-project"

    def detect(self, project_dir: Path) -> bool:
        """Return True if this is a my-project repo."""
        return (project_dir / "my-project.yaml").exists()

    def get_metrics_history(
        self, project_dir: Path, start_time: str
    ) -> list[MetricsEntry]:
        """Read project-specific metrics from existing outputs."""
        # Parse your project's output files
        return []

    def check_convergence(
        self, metrics_history: list[MetricsEntry]
    ) -> ConvergenceResult:
        """Apply project-specific convergence logic."""
        return ConvergenceResult(
            should_continue=True,
            reason="Still exploring",
            confidence=0.0  # Defer to RSSI
        )

    def get_session_mode(self) -> str:
        return "my-project-research"
```

The registry auto-discovers adapters on `/ralph:start` - no registration needed.

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
│   ├── core/                   # Adapter infrastructure
│   │   ├── protocols.py        # ProjectAdapter protocol
│   │   ├── registry.py         # Auto-discovery registry
│   │   └── path_hash.py        # Session state isolation
│   ├── adapters/               # Project-type adapters
│   │   ├── universal.py        # Fallback (RSSI behavior)
│   │   └── alpha_forge.py      # Alpha Forge adapter
│   ├── templates/              # Prompt templates (Jinja2 markdown)
│   │   ├── validation-round-1.md
│   │   ├── validation-round-2.md
│   │   ├── validation-round-3.md
│   │   ├── exploration-mode.md
│   │   ├── implementation-mode.md
│   │   ├── status-header.md
│   │   └── alpha-forge-convergence.md
│   └── tests/                  # Test suite
│       ├── test_adapters.py    # Adapter system tests
│       ├── test_completion.py
│       ├── test_validation.py
│       └── test_utils.py
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
uv run tests/test_adapters.py      # Adapter system (20 tests)

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
| adapters      | Registry discovery, path hash, Alpha Forge convergence  |

## Related

- [Geoffrey Huntley's Article](https://ghuntley.com/ralph/) - Original technique
