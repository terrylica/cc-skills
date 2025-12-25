# Ralph Mental Model for Alpha-Forge

> **TL;DR**: Ralph keeps Claude researching ML strategies autonomously for hours/days by intercepting stop attempts and injecting systematic OODA prompts.

## What Ralph Does

**Without Ralph**: Claude finishes one task → stops → you restart manually

**With Ralph**: Claude finishes one task → Ralph says "not done yet, here's your next research action" → Claude continues → repeat for 9+ hours until research converges

Ralph transforms Claude from a **single-task assistant** into an **autonomous ML researcher** that systematically explores model architectures, hyperparameters, and SOTA techniques.

---

## The Stop Hook

Every time Claude tries to stop, Ralph intercepts and decides:

```
┌─────────────────────────────────────────────────────────────┐
│                    RALPH STOP HOOK                          │
│                                                             │
│  Claude attempts to stop                                    │
│         ↓                                                   │
│  Ralph intercepts (loop-until-done.py)                      │
│         ↓                                                   │
│  ┌─────────────────────────────────────┐                    │
│  │ "Is the task complete?"             │                    │
│  │  - Check plan checkboxes            │                    │
│  │  - Check research_log.md CONVERGED  │                    │
│  └─────────────────────────────────────┘                    │
│         ↓ NO                    ↓ YES                       │
│  Block stop,              ┌─────────────────────────┐       │
│  inject OODA prompt       │ "Hit time/iteration     │       │
│         ↓                 │  limits?" (min 9h, 99i) │       │
│  Claude continues         └─────────────────────────┘       │
│                                 ↓ NO           ↓ YES        │
│                           Block stop,      Allow stop       │
│                           inject prompt                     │
└─────────────────────────────────────────────────────────────┘
```

---

## OODA Research Loop

When Ralph blocks a stop, it injects this research methodology:

| Phase       | What Claude Does                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------ |
| **OBSERVE** | Read `research_summary.md` (metrics), `research_log.md` (recommendations), `best_configs/*.yaml` |
| **ORIENT**  | Synthesize expert recommendations, check ROADMAP alignment, self-critique assumptions            |
| **DECIDE**  | Apply decision formula (see below)                                                               |
| **ACT**     | Execute `/research strategy.yaml` — **MANDATORY every iteration**                                |

### Decision Formula

| Condition                        | Action                                                            |
| -------------------------------- | ----------------------------------------------------------------- |
| WFE < 0.5                        | **FIX** — Add regularization, reduce complexity                   |
| Sharpe delta < 5% for 2 sessions | **PIVOT** — WebSearch for new technique → implement → `/research` |
| Sharpe delta > 10%               | **CONTINUE** — Evolve current config                              |
| Sharpe regressed > 20%           | **REVERT** — Use previous working config                          |

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

## Configuration

**Location**: `alpha-forge/.claude/ralph-config.json`

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

| File                                      | Ralph Reads/Writes | Purpose                       |
| ----------------------------------------- | ------------------ | ----------------------------- |
| `.claude/ralph-config.json`               | Reads              | Loop limits and guidance      |
| `.claude/STOP_LOOP`                       | Reads              | Kill switch (presence = stop) |
| `outputs/runs/run_*/summary.json`         | Reads              | Sharpe, WFE, metrics          |
| `research_sessions/*/research_log.md`     | Reads              | CONVERGED status              |
| `research_sessions/*/research_summary.md` | Reads              | Metrics history               |
| `best_configs/*.yaml`                     | Reads              | Top performing strategies     |

---

## Data Sources

Ralph enforces real data only during research:

- **gapless-crypto-clickhouse** — Primary ClickHouse data source
- **data/cache/** — Cached Binance Spot/Futures OHLCV
- **FORBIDDEN**: Synthetic data (`np.random`), live feeds, paper trading

---

**For technical implementation details**: See [README.md](./README.md)

**For architecture decisions**: See [RSSI Eternal Loop ADR](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)
