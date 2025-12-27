# Ralph Plugin for Claude Code

Keep Claude Code working autonomously — implements the Ralph Wiggum technique as Claude Code hooks with **RSSI** (Recursively Self-Improving Superintelligence) capabilities. RSSI transcends AGI: while AGI matches human capability, RSSI recursively improves itself toward ASI (Artificial Superintelligence).

> **First time here?** Start with [GETTING-STARTED.md](./GETTING-STARTED.md) — a step-by-step guide for new users covering plugin installation, hook setup, and your first Ralph session.

> **Already familiar with Ralph?** See [Mode Progression](#mode-progression-rssi--beyond-agi) for RSSI behavior, or [MENTAL-MODEL.md](./MENTAL-MODEL.md) for Alpha-Forge ML research workflows.

## What This Plugin Does

This plugin adds autonomous loop mode to Claude Code through 8 commands and 3 hooks:

**Commands:**

- `/ralph:start` - Enable loop mode (Claude continues working)
- `/ralph:stop` - Disable loop mode immediately
- `/ralph:status` - Show current loop state and metrics
- `/ralph:config` - View/modify runtime limits
- `/ralph:hooks` - Install/uninstall hooks to settings.json

**Interjection Commands** (modify guidance mid-loop):

- `/ralph:encourage` - Add item to encouraged list (prioritized)
- `/ralph:forbid` - Add item to forbidden list (blocked)
- `/ralph:audit-now` - Force immediate validation round

**Hooks:**

- **Stop hook** (`loop-until-done.py`) - RSSI-enhanced autonomous operation with zero idle tolerance
- **PreToolUse hook** (`archive-plan.sh`) - Archives `.claude/plans/*.md` files before overwrite
- **PreToolUse hook** (`pretooluse-loop-guard.py`) - Guards loop control files from deletion

## Design Philosophy

Core principles guiding Ralph Wiggum's development:

### High-Impact Work Only

1. **No Busywork** — Linting, formatting, type hints, docstrings, test coverage hunting, and refactoring for "readability" are FORBIDDEN. Every action must directly improve OOD-robust performance.

2. **SOTA Evidence-Based** — All improvements must be grounded in SOTA (State-Of-The-Art) research. Use WebSearch to find 2024-2025 papers, GitHub repos, and tutorials before implementing. No guessing or ad-hoc solutions.

3. **OOD-Robust Performance** — The goal is OOD (Out-Of-Distribution) robustness: Sharpe ratio, WFE (Walk-Forward Efficiency), and drawdown that generalize beyond training data. Distribution-shift resilience trumps in-sample metrics.

### Autonomous Operation

1. **Never Idle** — Ralph always finds or creates improvement opportunities. Saying "monitoring", "waiting", or "no work available" is forbidden. Immediate forced exploration on first idle signal.

2. **Knowledge Accumulates** — Each iteration builds on previous discoveries. Patterns, effective checks, and feature ideas persist across sessions.

3. **Multi-Signal Decisions** — Completion requires multiple confidence signals (explicit markers, checkboxes, semantic phrases), not single indicators.

### Alpha Forge Optimized

1. **Alpha Forge First** — Ralph has specialized adapter support for Alpha Forge projects with metrics-based convergence detection. Other projects use RSSI completion detection.

2. **User Override Always Wins** — Kill switch (`.claude/STOP_LOOP`), `/ralph:stop`, and manual intervention always work. The loop is eternal but never inescapable.

## Alpha-Forge Exclusivity (v8.0.2+)

Ralph hooks are designed **exclusively** for Alpha Forge ML research workflows:

| Project Type        | Hook Behavior                                           |
| ------------------- | ------------------------------------------------------- |
| **Alpha Forge**     | Full RSSI functionality, adapter convergence, OODA loop |
| **Non-Alpha Forge** | Silent pass-through (zero processing, zero overhead)    |

**Detection Criteria** (any match = alpha-forge):

- `pyproject.toml` contains `alpha-forge` or `alpha_forge`
- `packages/alpha-forge-core/` directory exists
- `outputs/runs/` directory exists
- Parent directories contain markers (handles git worktrees)

**Why this design**: Ralph's RSSI loop, OODA research methodology, and metrics-based convergence are specifically tailored for Alpha Forge's experiment-driven ML research. Applying these patterns to unrelated projects would be counterproductive.

## Quick Start

```bash
# 1. Install hooks (records timestamp for restart detection)
/ralph:hooks install

# 2. CRITICAL: Restart Claude Code (hooks only load at startup)
#    Exit Claude Code completely and relaunch

# 3. Verify installation with preflight checks
/ralph:hooks status

# 4. Start the loop
/ralph:start

# Claude will now continue working until:
# - Maximum time/iterations reached (safety guardrail)
# - You run /ralph:stop or create .claude/STOP_LOOP
#
# Note: Task completion and adapter convergence DO NOT stop the loop —
# they trigger exploration mode (RSSI eternal loop behavior).
```

## Installation Verification (v7.19.0+)

Ralph includes comprehensive preflight checks to ensure proper installation before starting autonomous mode.

### Preflight Checks

Run `/ralph:hooks status` to verify your installation:

```
=== Ralph Hooks Preflight Check ===

Plugin Location:
  ✓ Found at: ~/.claude/plugins/cache/cc-skills/ralph/7.19.0
    Source: GitHub install (cache path)

Dependencies:
  ✓ jq 1.7.1
  ✓ uv 0.5.11
  ✓ Python 3.11

Hook Scripts:
  ✓ loop-until-done.py (executable)
  ✓ archive-plan.sh (executable)
  ✓ pretooluse-loop-guard.py (executable)

Hook Registration:
  ✓ 3 hook(s) registered in settings.json

Session Status:
  ✓ Hooks were installed before this session

=== Summary ===
All preflight checks passed!
Ralph is ready to use. Run: /ralph:start
```

### Restart Detection

Ralph enforces restart after hook installation. If you run `/ralph:start` without restarting:

```
ERROR: Hooks were installed AFTER this session started!
       The Stop hook won't run until you restart Claude Code.

ACTION: Exit and restart Claude Code, then run /ralph:start again
```

**Why this matters**: Claude Code loads hooks at startup. Installing hooks mid-session means they won't activate until restart.

### Path Auto-Detection

Ralph automatically finds its hooks regardless of installation method:

| Installation Method        | Path                                                      |
| -------------------------- | --------------------------------------------------------- |
| GitHub (`/plugin install`) | `~/.claude/plugins/cache/cc-skills/ralph/<VERSION>/`      |
| Marketplace (local dev)    | `~/.claude/plugins/marketplaces/cc-skills/plugins/ralph/` |
| Environment variable       | `$CLAUDE_PLUGIN_ROOT`                                     |

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

### Mode Progression (RSSI — Beyond AGI)

Ralph implements **Recursively Self-Improving Superintelligence (RSSI)** — the Intelligence Explosion mechanism (I.J. Good, 1965). RSSI never stops on success; it pivots to find new frontiers.

```
IMPLEMENTATION (working on checklist)
       ↓
   [task_complete = True]
       ↓
EXPLORATION (discovery + recursive self-improvement)
       ↓
   [continues indefinitely until user stops or limits reached]
```

**RSSI Behavior** (task/adapter completion → exploration, not stop):

| Event                | Traditional | RSSI (Beyond AGI)           |
| -------------------- | ----------- | --------------------------- |
| Task completion      | Stop        | → Pivot to exploration      |
| Adapter convergence  | Stop        | → Pivot to exploration      |
| Loop detection (99%) | Stop        | → Continue with exploration |
| Max time/iterations  | Stop        | ✅ Stop (safety guardrail)  |
| `/ralph:stop`        | Stop        | ✅ Stop (user override)     |

> "The first ultraintelligent machine is the last invention that man need ever make." — I.J. Good, 1965

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

### 5-Round Validation System (v7.13.0+)

When `/ralph:audit-now` is invoked or validation is triggered, Ralph runs a comprehensive 5-round validation:

| Round | Focus                       | What It Checks                                  |
| ----- | --------------------------- | ----------------------------------------------- |
| 1     | **Critical Issues**         | Ruff errors, import failures, syntax errors     |
| 2     | **Verification**            | Verify fixes, regression detection              |
| 3     | **Documentation**           | Docstrings, coverage gaps, outdated docs        |
| 4     | **Adversarial Probing**     | Edge cases, math validation (Sharpe/WFE bounds) |
| 5     | **Cross-Period Robustness** | Bull/Bear/Sideways market regime testing        |

**Score Threshold**: Validation completes when score >= 0.8 (configurable).

**Math Guards** (Round 4): Runtime validators check for impossible values:

- Sharpe ratio: Must be within [-5, 10] (beyond = data issue)
- WFE: Must be within [0, 2] (beyond = overfitting)
- Drawdown: Must be within [0, 1] (beyond = calculation error)

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

**Loop Detection**: Uses [RapidFuzz](https://github.com/rapidfuzz/RapidFuzz) (`fuzz.ratio()` - Levenshtein-based similarity) to compare Claude's outputs. Triggers exploration mode if outputs are >99% similar across a 5-iteration window.

- **Tool**: RapidFuzz v3.x (MIT license, 9k+ GitHub stars)
- **Algorithm**: `fuzz.ratio()` returns 0-100% similarity based on edit distance
- **Data Source**: Anthropic's Claude Code JSONL transcript (`hook_input["transcript_path"]`)
- **What's Monitored**: Last assistant message content (first 1000 chars) from each iteration
- **Storage**: Ralph's state file (`recent_outputs` array, last 5 entries)

The high 99% threshold enables RSSI's Intelligence Explosion — only near-identical outputs (exact duplicates or trivial whitespace differences) trigger a pivot. Synonym swaps, added sentences, or different phrasing (which score 90-98%) continue normally.

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

**Note**: Non-Alpha Forge projects are skipped entirely — Ralph hooks pass through silently with zero overhead (see [Alpha-Forge Exclusivity](#alpha-forge-exclusivity-v802)).

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
├── MENTAL-MODEL.md             # Alpha Forge ML research mental model
├── commands/                   # Slash commands (8 total)
│   ├── start.md                # Enable loop mode
│   ├── stop.md                 # Disable loop mode
│   ├── status.md               # Show loop state
│   ├── config.md               # View/modify limits
│   ├── hooks.md                # Install/uninstall hooks + preflight checks
│   ├── encourage.md            # Add to encouraged list (interjection)
│   ├── forbid.md               # Add to forbidden list (interjection)
│   └── audit-now.md            # Force validation round (interjection)
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
│   │   ├── config_schema.py    # Dataclass config schema (not Pydantic)
│   │   └── path_hash.py        # Session state isolation + inheritance
│   ├── adapters/               # Alpha Forge adapter (exclusive)
│   │   └── alpha_forge.py      # Alpha Forge adapter
│   ├── templates/              # Prompt templates (Jinja2 markdown)
│   │   └── rssi-unified.md     # Unified RSSI template (all phases)
│   └── tests/                  # Test suite
│       ├── test_adapters.py    # Adapter system tests
│       ├── test_completion.py
│       └── test_utils.py
└── scripts/
    └── manage-hooks.sh         # Hook installation + path auto-detection
```

## Dependencies

**Required System Tools** (verified by `/ralph:hooks status`):

| Tool   | Version   | Purpose                         | Install                |
| ------ | --------- | ------------------------------- | ---------------------- |
| `uv`   | any       | Python package/script runner    | `brew install uv`      |
| `jq`   | any       | JSON processing for shell hooks | `brew install jq`      |
| Python | **3.11+** | Runtime for hook scripts        | `mise use python@3.11` |

**Python Packages** (PEP 723 inline dependencies in loop-until-done.py):

- `rapidfuzz>=3.0.0,<4.0.0` - Fuzzy string matching for loop detection
- `jinja2>=3.1.0,<4.0.0` - Template rendering for prompts

Dependencies are automatically installed by `uv` on first run. No manual pip install needed.

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

## Troubleshooting

### "Hooks were installed AFTER this session started"

**Cause**: You ran `/ralph:hooks install` and then `/ralph:start` without restarting Claude Code.

**Fix**: Exit Claude Code completely and relaunch, then run `/ralph:start`.

### "/ralph:hooks status" shows missing dependencies

**Fix**: Install required tools:

```bash
brew install uv jq
mise use python@3.11  # or: brew install python@3.11
```

### Hooks not found (GitHub install)

**Symptom**: `/ralph:hooks status` shows "Plugin NOT found" or scripts missing.

**Cause**: Plugin version mismatch or incomplete install.

**Fix**:

```bash
/plugin update    # Update to latest version
/ralph:hooks install  # Reinstall hooks
# Restart Claude Code
```

### Stop hook not firing

**Symptom**: Claude stops normally instead of continuing in loop mode.

**Debug**:

1. Check hooks are registered: `/ralph:hooks status`
2. Check loop is enabled: `cat .claude/loop-enabled`
3. Check for kill switch: `ls .claude/STOP_LOOP` (should not exist)

### Silent failures (no error output)

As of v7.19.0, all errors output to stderr. If you're on an older version:

```bash
/plugin update
```

## Related

- [Geoffrey Huntley's Article](https://ghuntley.com/ralph/) - Original technique
- [RSSI Eternal Loop ADR](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) - Core RSSI architecture
- [Stop Visibility ADR](/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) - 5-layer observability system
- [Dual Time Tracking ADR](/docs/adr/2025-12-22-ralph-dual-time-tracking.md) - Runtime vs wall-clock separation
