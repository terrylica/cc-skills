# Ralph Plugin for Claude Code

Keep Claude Code working autonomously until tasks are complete - implements the Ralph Wiggum technique as Claude Code hooks with **RSSI** (Recursively Self-Improving Super Intelligence) capabilities.

## What This Plugin Does

This plugin adds autonomous loop mode to Claude Code through 5 commands and 3 hooks:

**Commands:**

- `/ralph:start` - Enable loop mode (Claude continues working)
- `/ralph:stop` - Disable loop mode immediately
- `/ralph:status` - Show current loop state and metrics
- `/ralph:config` - View/modify runtime limits
- `/ralph:hooks` - Install/uninstall hooks to settings.json

**Hooks:**

- **Stop hook** (`loop-until-done.py`) - RSSI-enhanced autonomous operation with zero idle tolerance
- **PreToolUse hook** (`archive-plan.sh`) - Archives `.claude/plans/*.md` files before overwrite
- **PreToolUse hook** (`pretooluse-loop-guard.py`) - Guards loop control files from deletion

## Design Philosophy

Core principles guiding Ralph Wiggum's development:

### High-Impact Work Only

1. **No Busywork** — Linting, formatting, type hints, docstrings, test coverage hunting, and refactoring for "readability" are FORBIDDEN. Every action must directly improve OOD-robust performance.

2. **SOTA Evidence-Based** — All improvements must be grounded in state-of-the-art research. Use WebSearch to find 2024-2025 papers, GitHub repos, and tutorials before implementing. No guessing or ad-hoc solutions.

3. **OOD-Robust Performance** — The goal is out-of-distribution robustness: Sharpe ratio, WFE (Walk-Forward Efficiency), and drawdown that generalize beyond training data. Distribution-shift resilience trumps in-sample metrics.

### Autonomous Operation

1. **Never Idle** — Ralph always finds or creates improvement opportunities. Saying "monitoring", "waiting", or "no work available" is forbidden. Immediate forced exploration on first idle signal.

2. **Knowledge Accumulates** — Each iteration builds on previous discoveries. Patterns, effective checks, and feature ideas persist across sessions.

3. **Multi-Signal Decisions** — Completion requires multiple confidence signals (explicit markers, checkboxes, semantic phrases), not single indicators.

### Alpha Forge Exclusive

1. **Single Project Focus** — Ralph Wiggum is dedicated exclusively to `~/eon/alpha-forge` ([EonLabs-Spartan/alpha-forge](https://github.com/EonLabs-Spartan/alpha-forge)). No generic adapter system.

2. **User Override Always Wins** — Kill switch (`.claude/STOP_LOOP`), `/ralph:stop`, and manual intervention always work. The loop is eternal but never inescapable.

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

### Hook Architecture

Ralph uses 3 Claude Code hooks working together:

```
┌─────────────────────────────────────────────────────────────────┐
│                    RALPH HOOK SYSTEM                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PreToolUse Hooks (fire BEFORE tool execution)                  │
│  ┌─────────────────────┐   ┌─────────────────────┐             │
│  │ archive-plan.sh     │   │ pretooluse-loop-    │             │
│  │ (Write|Edit)        │   │ guard.py (Bash)     │             │
│  │                     │   │                     │             │
│  │ Archives plan files │   │ Blocks deletion of  │             │
│  │ before overwrite    │   │ loop control files  │             │
│  └─────────────────────┘   └─────────────────────┘             │
│                                                                 │
│  Stop Hook (fires when Claude attempts to stop)                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    loop-until-done.py                    │   │
│  │                                                          │   │
│  │  1. Check kill switch (.claude/STOP_LOOP)               │   │
│  │  2. Check max time/iterations                           │   │
│  │  3. Zero idle tolerance (force exploration)             │   │
│  │  4. Task completion detection (multi-signal)            │   │
│  │  5. Adapter convergence (Alpha Forge)                   │   │
│  │  6. Return prompt for next action OR allow stop         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Hook Flow**:

1. User runs `/ralph:start` → Creates `.claude/loop-enabled` + config
2. Claude works on tasks, Stop hook fires when Claude finishes
3. Stop hook returns `{"decision": "block", "reason": "..."}` with next prompt
4. Claude continues working (loop repeats)
5. Stop hook returns `{}` (empty) when truly complete → Session ends

### Mode Progression (RSSI Workflow)

```
IMPLEMENTATION (working on checklist)
       ↓
   [task_complete = True]
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

### Exploration/Discovery Mode

After task completion, if minimum time/iterations not met:

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

**Zero Idle Tolerance**: Prevents "monitoring" loops with immediate action:

- Detects idle outputs ("Work Item: None", "no SLO-aligned work")
- Immediately forces exploration mode on first idle signal
- No waiting, no backoff — always take action

**Loop Guard**: PreToolUse hook prevents Claude from deleting loop control files (`.claude/loop-enabled`, etc.)

**Kill Switch**: Create `.claude/STOP_LOOP` in project root for immediate termination:

```bash
touch .claude/STOP_LOOP  # Emergency stop
```

### Stop Visibility Observability (v7.7.0+)

Ralph implements a 5-layer observability system to ensure users always know when and why sessions stop:

| Layer | Feature                                    | Visibility                                      |
| ----- | ------------------------------------------ | ----------------------------------------------- |
| 1     | stderr notification                        | Terminal (immediate)                            |
| 2     | Cache file with session correlation        | Persistent (`~/.claude/ralph-stop-reason.json`) |
| 3     | Progress headers with warnings             | Claude sees in continuation prompt              |
| 4     | `/ralph:status` displays last stop reason  | On-demand check                                 |
| 5     | Automatic cache clearing on `/ralph:start` | Fresh slate per session                         |

**Terminal Output** (stderr - visible to user, not Claude):

```
[RALPH] Session stopped: Maximum runtime (9h) reached
```

**Approaching Limits Warning** (in continuation prompt):

```
**IMPLEMENTATION** | Iteration 95/99 | Runtime: 8.5h/9.0h | Wall: 12.0h | 0.0h / 0 iters to min
**WARNING**: Approaching limits (0.5h / 4 iters to max)
```

**Post-Session** (`/ralph:status`):

```
=== Last Stop Reason ===
Type: Normal
Reason: Maximum runtime (9h) reached
Time: 2025-12-22T21:32:27Z
Session: cbe3a408...
```

### Dual Time Tracking (v7.9.0+)

Ralph tracks **two time metrics** to ensure accurate limit enforcement even when the CLI is closed:

| Metric         | Description                        | Used For              |
| -------------- | ---------------------------------- | --------------------- |
| **Runtime**    | CLI active time (excludes pauses)  | Limit enforcement     |
| **Wall-clock** | Calendar time since `/ralph:start` | Informational display |

**Why this matters**: If you close Claude Code overnight:

- Start at 6 PM, work 2 hours, close at 8 PM
- Reopen at 8 AM next day (12 hours later)
- **Before v7.9.0**: "Maximum runtime (9h) reached" after only 2 hours of work
- **After v7.9.0**: Runtime shows 2.0h, wall-clock shows 14.0h — limits use runtime

**Display Format** (in continuation prompt):

```
**IMPLEMENTATION** | Iteration 42/99 | Runtime: 3.2h/9.0h | Wall: 15.0h | 0.8h / 8 iters to min
```

**Gap Detection**: If more than 5 minutes pass between Stop hook calls, the CLI was closed — that time is excluded from runtime.

**Status Display** (`/ralph:status`):

```
=== Time Tracking ===
Runtime (CLI active): 3.20h
Wall-clock (since start): 15.00h

Note: Runtime = actual CLI working time (pauses excluded)
      Wall-clock = calendar time since /ralph:start
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
│   ├── start.md                # Enable loop mode
│   ├── stop.md                 # Disable loop mode
│   ├── status.md               # Show loop state
│   ├── config.md               # View/modify limits
│   └── hooks.md                # Install/uninstall hooks
├── hooks/                      # Hook implementations (modular)
│   ├── hooks.json              # Hook registration (3 hooks)
│   ├── loop-until-done.py      # Stop hook (main orchestrator, zero idle tolerance)
│   ├── archive-plan.sh         # PreToolUse hook (Write|Edit) - plan archival
│   ├── pretooluse-loop-guard.py # PreToolUse hook (Bash) - file protection
│   ├── completion.py           # Multi-signal completion detection
│   ├── discovery.py            # File discovery & work scanning
│   ├── utils.py                # Time tracking, loop detection
│   ├── template_loader.py      # Jinja2 template rendering
│   ├── core/                   # Adapter infrastructure
│   │   ├── protocols.py        # ProjectAdapter protocol
│   │   ├── registry.py         # Auto-discovery registry
│   │   ├── config_schema.py    # Pydantic config models
│   │   └── path_hash.py        # Session state isolation
│   ├── adapters/               # Alpha Forge adapter (exclusive)
│   │   └── alpha_forge.py      # Alpha Forge adapter
│   ├── templates/              # Prompt templates (Jinja2 markdown)
│   │   ├── implementation-mode.md   # Basic task continuation
│   │   ├── exploration-mode.md      # RSSI eternal loop
│   │   ├── alpha-forge-exploration.md # Alpha Forge OODA loop
│   │   └── alpha-forge-convergence.md # Convergence prompts
│   └── tests/                  # Test suite
│       ├── test_adapters.py    # Adapter system tests
│       ├── test_completion.py
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
uv run tests/test_utils.py         # Loop detection, time tracking
uv run tests/test_integration.py   # Full workflow simulation
uv run tests/test_adapters.py      # Adapter system (20 tests)

# Run POC task
/ralph:start -f plugins/ralph/hooks/tests/poc-task.md --poc
```

**Test Coverage**:

| Module        | Tests                                                   |
| ------------- | ------------------------------------------------------- |
| completion.py | Explicit markers, checkboxes, frontmatter, RSSI signals |
| utils.py      | Elapsed hours, loop detection, section extraction       |
| integration   | Mode transitions, file discovery, workflow simulation   |
| adapters      | Registry discovery, path hash, Alpha Forge convergence  |

## Related

- [Geoffrey Huntley's Article](https://ghuntley.com/ralph/) - Original technique
