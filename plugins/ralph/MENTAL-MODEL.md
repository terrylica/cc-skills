# Ralph Mental Model for Alpha-Forge

> **Scope**: This document describes Ralph's mental model for **Alpha-Forge** (quantitative research). For generic Ralph behavior (non-Alpha-Forge projects), see [README.md](./README.md#how-it-works).

> **TL;DR**: Ralph implements **RSSI** (Recursively Self-Sustaining Iteration) — keeping Claude researching autonomously by intercepting stop attempts and pivoting to exploration. Convergence triggers new frontiers, not stopping.

## RSSI — Aspirational Framing

> **Important**: RSSI is **aspirational framing**, not literal implementation. Ralph does not implement AGI, ASI, or a true "intelligence explosion." It's a Stop hook that blocks premature stopping and injects a continuation prompt. The terminology below is metaphorical — describing the _intent_ of autonomous iteration, not claiming superintelligence.

Ralph's design is inspired by the **Intelligence Explosion** concept (I.J. Good, 1965). The "RSSI" framing captures the goal: recursive improvement through continuous research iteration.

> "The first ultraintelligent machine is the last invention that man need ever make."
> — I.J. Good, 1965

**Key Behavior**: Task completion and adapter convergence **pivot to exploration** instead of stopping. Ralph never stops on success — it finds new frontiers.

| Event                | Traditional | RSSI (Ralph)                |
| -------------------- | ----------- | --------------------------- |
| Task completion      | Stop        | → Pivot to exploration      |
| Adapter convergence  | Stop        | → Pivot to exploration      |
| Loop detection (99%) | Stop        | → Continue with exploration |
| Max time/iterations  | Stop        | ✅ Stop (safety guardrail)  |
| `/ralph:stop`        | Stop        | ✅ Stop (user override)     |

**Alpha-Forge Exception**: After `min_hours` (9h default) of deep research, genuine convergence (Status: CONVERGED in `research_log.md`) allows graceful session end. This represents successful research completion — the RSSI has exhausted improvement frontiers after extensive exploration. See [Convergence Detection](#convergence-detection) for the specific flow.

---

## What Ralph Does

**Without Ralph**: Claude finishes one task → stops → you restart manually

**With Ralph**: Claude finishes one task → Ralph pivots to exploration → Claude finds new improvements → repeat indefinitely (RSSI eternal loop)

Ralph transforms Claude from a **single-task assistant** into an **autonomous research agent** that systematically explores and iteratively improves.

---

## Session Lifecycle

```
           Ralph Alpha-Forge Workflow

         ╔════════════════════════════╗
         ║        Kill Switch         ║
         ╚════════════════════════════╝
           │
           │ .claude/STOP_LOOP
           ∨
         ╭────────────────────────────╮
         │        Stop Session        │   <┐
         ╰────────────────────────────╯    │
         ╭────────────────────────────╮    │
         │     Start /ralph:start     │    │
         ╰────────────────────────────╯    │
           │                               │
           │                               │
           ∨                               │
       ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐  │
       ╎ Configuration:                 ╎  │
       ╎                                ╎  │
       ╎ ┌────────────────────────────┐ ╎  │
       ╎ │        Read Config         │ ╎  │
       ╎ └────────────────────────────┘ ╎  │
       ╎                                ╎  │
       └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘  │
           │                               │
           │ .claude/ralph-config.json     │
           ∨                               │
         ┌────────────────────────────┐    │
         │       Detect Project       │    │
         └────────────────────────────┘    │
           │                               │
           │ pyproject.toml                │
           ∨                               │
       ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐  │
       ╎ Work Discovery:                ╎  │
       ╎                                ╎  │
       ╎ ┌────────────────────────────┐ ╎  │
       ╎ │    Alpha Forge Adapter     │ ╎  │
       ╎ └────────────────────────────┘ ╎  │
       ╎                                ╎  │
       └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘  │
           │                               │
           │ ROADMAP.md                    │
           ∨                               │
       ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐  │ YES
       ╎ OODA Research Loop:            ╎  │
       ╎                                ╎  │
       ╎ ┌────────────────────────────┐ ╎  │
  ┌──> ╎ │         OODA Loop          │ ╎  │
  │    ╎ └────────────────────────────┘ ╎  │
  │    ╎                                ╎  │
  │    └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘  │
  │        │                               │
  │        │                               │
  │        ∨                               │
  │      ┌────────────────────────────┐    │
  │      │         O: Observe         │    │
  │      └────────────────────────────┘    │
  │        │                               │
  │        │                               │
  │        ∨                               │
  │      ┌────────────────────────────┐    │
  │      │         O: Orient          │    │
  │      └────────────────────────────┘    │
  │ NO     │                               │
  │        │                               │
  │        ∨                               │
  │      ┌────────────────────────────┐    │
  │      │         D: Decide          │    │
  │      └────────────────────────────┘    │
  │        │                               │
  │        │                               │
  │        ∨                               │
  │      ┌────────────────────────────┐    │
  │      │           A: Act           │    │
  │      └────────────────────────────┘    │
  │        │                               │
  │        │                               │
  │        ∨                               │
  │      ┌────────────────────────────┐    │
  └───   │      Check Converged       │   ─┘
         └────────────────────────────┘
```

> **Note**: This diagram shows the simplified Alpha-Forge flow. The "YES" path from Check Converged to Stop Session only activates **after `min_hours`** (9h). Before that threshold, convergence pivots to exploration (see [Convergence Detection](#convergence-detection) for detailed logic).

<details>
<summary>graph-easy source</summary>

```
graph { label: "Ralph Alpha-Forge Workflow"; flow: south; }

[Start /ralph:start] { shape: rounded; }
[Start /ralph:start] -> [Read Config]

( Configuration:
  [Read Config]
)
[Read Config] -- .claude/ralph-config.json --> [Detect Project]
[Detect Project] -- pyproject.toml --> [Alpha Forge Adapter]

( Work Discovery:
  [Alpha Forge Adapter]
)
[Alpha Forge Adapter] -- ROADMAP.md --> [OODA Loop]

( OODA Research Loop:
  [OODA Loop]
)
[OODA Loop] -> [O: Observe]
[O: Observe] -> [O: Orient]
[O: Orient] -> [D: Decide]
[D: Decide] -> [A: Act]
[A: Act] -> [Check Converged]

[Check Converged] -- NO --> [OODA Loop]
[Check Converged] -- YES (after min_hours) --> [Stop Session] { shape: rounded; }

[Kill Switch] { border: double; }
[Kill Switch] -- .claude/STOP_LOOP --> [Stop Session]
[Max Limits] { border: double; }
[Max Limits] -- max_hours/iterations --> [Stop Session]
```

</details>

---

## OODA Research Loop

> **Alpha-Forge Specific**: This section describes OODA guidance for quantitative research projects. The OODA phases are **template guidance** rendered into the RSSI prompt — Claude interprets and applies them, but there's no hardcoded enforcement.

When Ralph blocks a stop, it injects this research methodology:

| Phase       | What Claude Does                                                                                                                                                                                                                                                                              |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OBSERVE** | Read `research_summary.md` _(local)_, [`ROADMAP.md`](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/ROADMAP.md), `outputs/runs/summary.json` _(local)_                                                                                                                              |
| **ORIENT**  | Synthesize expert recommendations from `research_log.md`, check ROADMAP alignment, review `deferred_recommendations` and `SOTA Queue`                                                                                                                                                         |
| **DECIDE**  | Apply decision formula based on Sharpe/WFE metrics (see below)                                                                                                                                                                                                                                |
| **ACT**     | Execute `/research strategy.yaml` using templates from [`examples/03_machine_learning/`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/examples/03_machine_learning), write code to [`src/alpha_forge/`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge) |

### OODA File Access

```
                                                 OODA Phase File Access

┌───────────────────────────────┐     ┌───────────────────────────┐     ┌─────────────────────────┐
│       src/alpha_forge/        │ <── │            ACT            │ ──> │    /research command    │
└───────────────────────────────┘     └───────────────────────────┘     └─────────────────────────┘
                                        │
                                        │
                                        ∨
                                      ┌───────────────────────────┐
                                      │      examples/*.yaml      │
                                      └───────────────────────────┘
                                      ┌───────────────────────────┐     ┌─────────────────────────┐
                                      │          DECIDE           │ ──> │ summary.json Sharpe/WFE │
                                      └───────────────────────────┘     └─────────────────────────┘

                                        ┌────────────────────────────────────────────────────────────┐
                                        │                                                            ∨
┌───────────────────────────────┐     ┌───────────────────────────┐     ┌─────────────────────────┐┌─────────────────────┐
│        research_log.md        │ <── │          OBSERVE          │ ──> │       ROADMAP.md        ││ research_summary.md │
└───────────────────────────────┘     └───────────────────────────┘     └─────────────────────────┘└─────────────────────┘
                                        │
                                        │
                                        ∨
                                      ┌───────────────────────────┐
                                      │ outputs/runs/summary.json │
                                      └───────────────────────────┘
┌───────────────────────────────┐     ┌───────────────────────────┐     ┌─────────────────────────┐
│ research_log.md deferred_recs │ <── │          ORIENT           │ ──> │  ROADMAP.md priorities  │
└───────────────────────────────┘     └───────────────────────────┘     └─────────────────────────┘
                                        │
                                        │
                                        ∨
                                      ┌───────────────────────────┐
                                      │        SOTA Queue         │
                                      └───────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "OODA Phase File Access"; flow: east; }

[OBSERVE] -> [research_summary.md]
[OBSERVE] -> [research_log.md]
[OBSERVE] -> [outputs/runs/summary.json]
[OBSERVE] -> [ROADMAP.md]

[ORIENT] -> [research_log.md deferred_recs]
[ORIENT] -> [SOTA Queue]
[ORIENT] -> [ROADMAP.md priorities]

[DECIDE] -> [summary.json Sharpe/WFE]

[ACT] -> [examples/*.yaml]
[ACT] -> [src/alpha_forge/]
[ACT] -> [/research command]
```

</details>

### Decision Formula

> **Template Guidance**: This decision tree is **conceptual guidance** rendered into the RSSI template. Claude uses it as a framework for reasoning — the thresholds are suggestions, not programmatically enforced rules.

```
                                     Decision Formula

                                                         ┌─────────────────────────┐
                                                         │      Check Metrics      │
                                                         └─────────────────────────┘
                                                           │
                                                           │
                                                           ∨
┌────────────────────────────────┐  YES                  ┌─────────────────────────┐
│    FIX: Add regularization     │ <──────────────────── │       WFE < 0.5?        │
└────────────────────────────────┘                       └─────────────────────────┘
                                                           │
                                                           │ NO
                                                           ∨
┌────────────────────────────────┐  YES for 2 sessions   ┌─────────────────────────┐
│ PIVOT: WebSearch new technique │ <──────────────────── │   Sharpe delta < 5%?    │
└────────────────────────────────┘                       └─────────────────────────┘
                                                           │
                                                           │ NO
                                                           ∨
                                                         ┌─────────────────────────┐
                                                         │   Sharpe delta > 10%?   │ ─┐
                                                         └─────────────────────────┘  │
                                                           │                          │
                                                           │ NO                       │
                                                           ∨                          │
┌────────────────────────────────┐  YES                  ┌─────────────────────────┐  │
│  REVERT: Use previous config   │ <──────────────────── │ Sharpe regressed > 20%? │  │ YES
└────────────────────────────────┘                       └─────────────────────────┘  │
                                                           │                          │
                                                           │ NO                       │
                                                           ∨                          │
                                                         ┌─────────────────────────┐  │
                                                         │ CONTINUE: Evolve config │ <┘
                                                         └─────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Decision Formula"; flow: south; }

[Check Metrics]
[Check Metrics] -> [WFE < 0.5?]
[WFE < 0.5?] -- YES --> [FIX: Add regularization]
[WFE < 0.5?] -- NO --> [Sharpe delta < 5%?]
[Sharpe delta < 5%?] -- YES for 2 sessions --> [PIVOT: WebSearch new technique]
[Sharpe delta < 5%?] -- NO --> [Sharpe delta > 10%?]
[Sharpe delta > 10%?] -- YES --> [CONTINUE: Evolve config]
[Sharpe delta > 10%?] -- NO --> [Sharpe regressed > 20%?]
[Sharpe regressed > 20%?] -- YES --> [REVERT: Use previous config]
[Sharpe regressed > 20%?] -- NO --> [CONTINUE: Evolve config]
```

</details>

---

## Convergence Detection

```
                             Convergence Detection

                                        ╭──────────────────────╮
                                        │ Stop Hook Triggered  │
                                        ╰──────────────────────╯
                                          │
                                          │
                                          ∨
                                        ┌──────────────────────┐
                                        │   Check STOP_LOOP    │ ─┐
                                        └──────────────────────┘  │
                                          │                       │
                                          │ no file               │
                                          ∨                       │
┏━━━━━━━━━━━━━━━━━━━━┓  under 9h        ┌──────────────────────┐  │
┃ Block: Inject OODA ┃ <─────────────── │    Check Min Time    │  │
┗━━━━━━━━━━━━━━━━━━━━┛                  └──────────────────────┘  │
  ∧                                       │                       │
  │                                       │ over 9h               │ file exists
  │                                       ∨                       │
  │                    not converged    ┌──────────────────────┐  │
  └──────────────────────────────────── │ Read research_log.md │  │
                                        └──────────────────────┘  │
                                          │                       │
                                          │ Status: CONVERGED     │
                                          ∨                       │
                                        ╭──────────────────────╮  │
                                        │      Allow Stop      │ <┘
                                        ╰──────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Convergence Detection"; flow: south; }

[Stop Hook Triggered] { shape: rounded; }
[Stop Hook Triggered] -> [Check STOP_LOOP]
[Check STOP_LOOP] -- file exists --> [Allow Stop] { shape: rounded; }
[Check STOP_LOOP] -- no file --> [Check Min Time]
[Check Min Time] -- under 9h --> [Block: Inject OODA] { border: bold; }
[Check Min Time] -- over 9h --> [Read research_log.md]
[Read research_log.md] -- Status: CONVERGED --> [Allow Stop]
[Read research_log.md] -- not converged --> [Block: Inject OODA]
```

</details>

---

## Busywork Blocking

Ralph filters out distractions during research:

| ✅ ALLOWED (Value-Aligned)  | ❌ BLOCKED (Busywork)      |
| --------------------------- | -------------------------- |
| Model architecture changes  | Linting fixes (ruff, mypy) |
| Hyperparameter tuning       | Documentation updates      |
| Feature engineering         | Test coverage expansion    |
| SOTA techniques (WebSearch) | CI/CD modifications        |
| Ensemble strategies         | Dependency upgrades        |
| Robustness testing          | Code style/formatting      |

When research status is **CONVERGED**, busywork is **hard-blocked** (cannot be chosen).

---

## Data Flow

> **Alpha-Forge Specific**: This section describes the data pipeline for quantitative research. Other projects have different data flows — Ralph adapts via project-specific adapters.

```
                                                                             Alpha-Forge Data Flow

┌────────────┐     ┌───────────────────────────┐     ┌─────────────┐     ┌─────────────────┐     ┌───────────────────────────┐     ┌─────────────────────┐     ┌───────────────┐
│ ClickHouse │ ──> │ gapless-crypto-clickhouse │ ──> │ data/cache/ │ ──> │ Backtest Engine │ ──> │ outputs/runs/summary.json │ ──> │ research_summary.md │ ──> │ Ralph OBSERVE │
└────────────┘     └───────────────────────────┘     └─────────────┘     └─────────────────┘     └───────────────────────────┘     └─────────────────────┘     └───────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Alpha-Forge Data Flow"; flow: east; }

[ClickHouse] -> [gapless-crypto-clickhouse]
[gapless-crypto-clickhouse] -> [data/cache/]
[data/cache/] -> [Backtest Engine]
[Backtest Engine] -> [outputs/runs/summary.json]
[outputs/runs/summary.json] -> [research_summary.md]
[research_summary.md] -> [Ralph OBSERVE]
```

</details>

**Data Sources**:

- [**gapless-crypto-clickhouse**](https://pypi.org/project/gapless-crypto-clickhouse/) — Primary ClickHouse data source (PyPI package)
- [**data/cache/**](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/data/cache) — Cached Binance Spot/Futures OHLCV
- **FORBIDDEN**: Synthetic data (`np.random`), live feeds, paper trading

---

## Time Tracking (v7.9.0+)

Ralph tracks **two time metrics** to ensure accurate limit enforcement even when the CLI is closed overnight:

| Metric         | Definition                         | Used For              |
| -------------- | ---------------------------------- | --------------------- |
| **Runtime**    | CLI active time (excludes pauses)  | All limit enforcement |
| **Wall-clock** | Calendar time since `/ralph:start` | Informational display |

**Gap Detection**: If more than 5 minutes pass between Stop hook calls, the CLI was closed — that time is excluded from runtime.

**Display Format** (in continuation prompt):

```
**RSSI — Beyond AGI** | Iteration 42/99 | Runtime: 3.2h/9.0h | Wall: 15.0h
```

---

## Session Continuity (v7.18.0+)

Ralph maintains state across Claude Code session transitions (auto-compacting, `/clear`, rate limit resets).

### How It Works

When a new session_id is detected for the same project:

1. **Check**: Does state file exist for current session?
2. **Inherit**: If not, find most recent state file with same project path hash
3. **Log**: Record inheritance to append-only JSONL log with hash chain
4. **Reset**: Clear per-session state (loop detection buffer)

### What Gets Inherited vs Reset

| State Field                   | Inherited? | Rationale                        |
| ----------------------------- | ---------- | -------------------------------- |
| `iteration`                   | ✅ Yes     | Continuity for min/max limits    |
| `accumulated_runtime_seconds` | ✅ Yes     | Accurate runtime tracking        |
| `started_at`                  | ✅ Yes     | Adapter metrics filtering        |
| `adapter_convergence`         | ✅ Yes     | Preserve research progress       |
| `recent_outputs`              | ❌ Reset   | Fresh loop detection per session |
| `validation_round`            | ❌ Reset   | Start validation fresh           |
| `idle_iteration_count`        | ❌ Reset   | Fresh idle detection             |

### Audit Trail

**Location**: `~/.claude/automation/loop-orchestrator/state/sessions/inheritance-log.jsonl`

```jsonl
{
  "timestamp": "2025-12-25T10:00:00Z",
  "child_session": "abc123",
  "parent_session": "xyz789@c7e0a029",
  "project_hash": "c7e0a029",
  "parent_hash": "sha256:1a2b3c4d...",
  "inherited_fields": [
    "iteration",
    "accumulated_runtime_seconds",
    "started_at",
    "adapter_convergence"
  ]
}
```

Each state file also includes `_inheritance` metadata:

```json
{
  "_inheritance": {
    "parent_session": "xyz789@c7e0a029.json",
    "parent_hash": "sha256:1a2b3c4d...",
    "inherited_at": "2025-12-25T11:30:00Z",
    "inherited_fields": [
      "iteration",
      "accumulated_runtime_seconds",
      "started_at",
      "adapter_convergence"
    ]
  }
}
```

**Verification**: Recompute SHA-256 hash of parent state and compare to stored `parent_hash` to detect tampering.

---

## Configuration

**Location**: [`.claude/ralph-config.json`](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/.claude/ralph-config.json)

```json
{
  "loop_limits": {
    "min_hours": 9,
    "max_hours": 999,
    "min_iterations": 99,
    "max_iterations": 999
  },
  "guidance": {
    "forbidden": [
      "Documentation updates",
      "Dependency upgrades",
      "Test coverage",
      "CI/CD"
    ],
    "encouraged": [
      "Research experiments",
      "SOTA time series forecasting",
      "OOD robust methodologies"
    ]
  }
}
```

### User Guidance (v8.7.0+)

The `guidance` section is rendered by the **unified RSSI template** (`rssi-unified.md`), which consolidated the previous dual-template architecture (implementation + exploration) into a single template.

**Key behavior**:

- Guidance appears in **ALL phases** (implementation and exploration)
- Uses Jinja2 `{% if task_complete %}` conditionals for phase-specific content
- Encouraged items **override** forbidden patterns
- Changes via `/ralph:encourage` and `/ralph:forbid` take effect on next iteration

**Kill Switch**: Create `.claude/STOP_LOOP` file to force stop immediately.

---

## Key Files in Alpha-Forge

> **Alpha-Forge Specific**: These files are specific to the Alpha-Forge quantitative research project. Other projects have different file structures and adapters.

| File                                                                                                                          | OODA Phase                | Ralph Action                                          |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------- |
| [ROADMAP.md](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/ROADMAP.md)                                             | OBSERVE, ORIENT           | Reads P0/P1/P2 priorities                             |
| [.claude/ralph-config.json](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/.claude/ralph-config.json)               | Session Start             | Reads limits, forbidden, encouraged, GPU              |
| `outputs/runs/*/summary.json` _(local runtime, gitignored)_                                                                   | OBSERVE, DECIDE           | Reads Sharpe, WFE, CAGR, maxDD, Sortino, Calmar       |
| `outputs/research_sessions/*/research_log.md` _(local runtime, gitignored)_                                                   | OBSERVE, ORIENT, Converge | Reads CONVERGED, deferred_recommendations, SOTA Queue |
| `outputs/research_sessions/*/research_summary.md` _(local runtime, gitignored)_                                               | OBSERVE                   | Reads metrics table                                   |
| [examples/03_machine_learning/\*.yaml](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/examples/03_machine_learning) | ACT                       | Reads template strategies                             |
| [src/alpha_forge/models/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge/models)                    | ACT                       | Writes model implementations                          |
| [src/alpha_forge/features/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge/features)                | ACT                       | Writes feature engineering                            |
| [pyproject.toml](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/pyproject.toml)                                     | Session Start             | Project detection                                     |
| [data/cache/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/data/cache)                                            | ACT                       | Data source for backtests                             |
| [.claude/agents/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/.claude/agents)                                    | Context                   | 15 agent definitions                                  |
| [.claude/commands/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/.claude/commands)                                | Context                   | 4 custom commands                                     |

---

**For technical implementation details**: See [README.md](./README.md)

**For architecture decisions**: See [RSSI Eternal Loop ADR](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)
