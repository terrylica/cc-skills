# Ralph Mental Model for Alpha-Forge

> **TL;DR**: Ralph keeps Claude researching ML strategies autonomously for hours/days by intercepting stop attempts and injecting systematic OODA prompts.

## What Ralph Does

**Without Ralph**: Claude finishes one task → stops → you restart manually

**With Ralph**: Claude finishes one task → Ralph says "not done yet, here's your next research action" → Claude continues → repeat for 9+ hours until research converges

Ralph transforms Claude from a **single-task assistant** into an **autonomous ML researcher** that systematically explores model architectures, hyperparameters, and SOTA techniques.

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
[Check Converged] -- YES --> [Stop Session] { shape: rounded; }

[Kill Switch] { border: double; }
[Kill Switch] -- .claude/STOP_LOOP --> [Stop Session]
```

</details>

---

## OODA Research Loop

When Ralph blocks a stop, it injects this research methodology:

| Phase       | What Claude Does                                                                                                                                                                                                                                                                                            |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OBSERVE** | Read [`research_summary.md`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/outputs/research_sessions), [`ROADMAP.md`](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/ROADMAP.md), [`outputs/runs/summary.json`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/outputs/runs) |
| **ORIENT**  | Synthesize expert recommendations from `research_log.md`, check ROADMAP alignment, review `deferred_recommendations` and `SOTA Queue`                                                                                                                                                                       |
| **DECIDE**  | Apply decision formula based on Sharpe/WFE metrics (see below)                                                                                                                                                                                                                                              |
| **ACT**     | Execute `/research strategy.yaml` using templates from [`examples/03_machine_learning/`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/examples/03_machine_learning), write code to [`src/alpha_forge/`](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge)               |

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

**Kill Switch**: Create `.claude/STOP_LOOP` file to force stop immediately.

---

## Key Files in Alpha-Forge

| File                                                                                                                                   | OODA Phase                | Ralph Action                                          |
| -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------- |
| [ROADMAP.md](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/ROADMAP.md)                                                      | OBSERVE, ORIENT           | Reads P0/P1/P2 priorities                             |
| [.claude/ralph-config.json](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/.claude/ralph-config.json)                        | Session Start             | Reads limits, forbidden, encouraged, GPU              |
| [outputs/runs/\*/summary.json](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/outputs/runs)                                  | OBSERVE, DECIDE           | Reads Sharpe, WFE, CAGR, maxDD, Sortino, Calmar       |
| [outputs/research_sessions/\*/research_log.md](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/outputs/research_sessions)     | OBSERVE, ORIENT, Converge | Reads CONVERGED, deferred_recommendations, SOTA Queue |
| [outputs/research_sessions/\*/research_summary.md](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/outputs/research_sessions) | OBSERVE                   | Reads metrics table                                   |
| [examples/03_machine_learning/\*.yaml](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/examples/03_machine_learning)          | ACT                       | Reads template strategies                             |
| [src/alpha_forge/models/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge/models)                             | ACT                       | Writes model implementations                          |
| [src/alpha_forge/features/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/src/alpha_forge/features)                         | ACT                       | Writes feature engineering                            |
| [pyproject.toml](https://github.com/EonLabs-Spartan/alpha-forge/blob/main/pyproject.toml)                                              | Session Start             | Project detection                                     |
| [data/cache/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/data/cache)                                                     | ACT                       | Data source for backtests                             |
| [.claude/agents/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/.claude/agents)                                             | Context                   | 15 agent definitions                                  |
| [.claude/commands/](https://github.com/EonLabs-Spartan/alpha-forge/tree/main/.claude/commands)                                         | Context                   | 4 custom commands                                     |

---

**For technical implementation details**: See [README.md](./README.md)

**For architecture decisions**: See [RSSI Eternal Loop ADR](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)
