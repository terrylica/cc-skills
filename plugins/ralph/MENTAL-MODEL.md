# Ralph Mental Model for Alpha-Forge

> **Scope**: This document describes Ralph's mental model for **Alpha-Forge** (quantitative research). For generic Ralph behavior (non-Alpha-Forge projects), see [README.md](./README.md#how-it-works).

> **TL;DR**: Ralph keeps Claude working autonomously instead of stopping after each task. When Claude finishes something, Ralph says "great, now find more improvements!" This creates continuous research sessions that can run for hours.
>
> **What RSSI means**: "Recursively Self-Sustaining Iteration" — a fancy way of saying "keeps going and keeps improving." You always have control: `/ralph:stop` or the kill switch (`.claude/STOP_LOOP` file) stops everything immediately.

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

### LoopState Machine

> **Simple Version**: Ralph has three modes: OFF, WORKING, and STOPPING. Think of it like a car: parked, driving, or coasting to a stop.

The loop controller manages three distinct states:

```
                LoopState Machine

          /ralph:start
             │
             ∨
┏━━━━━━━━━━━━━━━━━━━━━┓               ┏━━━━━━━━━━━━━━━━━━━━━┓
┃      STOPPED        ┃ ────────────> ┃      RUNNING        ┃
┗━━━━━━━━━━━━━━━━━━━━━┛               ┗━━━━━━━━━━━━━━━━━━━━━┛
  ∧                                     │
  │                                     │ /ralph:stop or
  │                                     │ max limits reached
  │                                     ∨
  │                   graceful       ┏━━━━━━━━━━━━━━━━━━━━━┓
  └───────────────── shutdown ────── ┃     DRAINING        ┃
                                     ┗━━━━━━━━━━━━━━━━━━━━━┛
```

| State        | What's Happening                        | User Can...                  |
| ------------ | --------------------------------------- | ---------------------------- |
| **STOPPED**  | Ralph is inactive, no hooks firing      | Start with `/ralph:start`    |
| **RUNNING**  | Hooks active, blocking stops, injecting | `/ralph:stop`, add guidance  |
| **DRAINING** | Finishing current work, then stopping   | Wait for graceful completion |

**State Transitions**:

- `STOPPED → RUNNING`: User runs `/ralph:start`
- `RUNNING → DRAINING`: `/ralph:stop`, kill switch, or limits exceeded
- `DRAINING → STOPPED`: Current iteration completes gracefully

<details>
<summary>graph-easy source</summary>

```
graph { label: "LoopState Machine"; flow: east; }

[STOPPED] { border: bold; }
[RUNNING] { border: bold; }
[DRAINING] { border: bold; }

[STOPPED] -- /ralph:start --> [RUNNING]
[RUNNING] -- /ralph:stop or limits --> [DRAINING]
[DRAINING] -- graceful shutdown --> [STOPPED]
```

</details>

### Hook Coordination

> **Simple Version**: Ralph has 3 hooks that work together like a relay team — each one has a specific job and they pass the baton in sequence.

Ralph uses three hooks that fire in a specific order:

```
                              Hook Coordination Sequence

                                  ╭─────────────────────────────────────────╮
                                  │          Claude wants to stop           │
                                  ╰─────────────────────────────────────────╯
                                    │
                                    │ Before any tool runs
                                    ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  HOOK 1: pretooluse-loop-guard.py                                              ┃
┃  ─────────────────────────────────                                             ┃
┃  "Should Claude even try to stop?"                                             ┃
┃  • Blocks stop attempts when loop is RUNNING                                   ┃
┃  • Allows stops when DRAINING or STOP_LOOP exists                              ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                                    │
                                    │ Before plan modifications
                                    ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  HOOK 2: archive-plan.sh                                                       ┃
┃  ───────────────────────                                                       ┃
┃  "Save work before modifying plans"                                            ┃
┃  • Archives plan files before they're changed                                  ┃
┃  • Creates timestamped backups in tmp/                                         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                                    │
                                    │ When Claude tries to end session
                                    ∨
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  HOOK 3: loop-until-done.py (Stop Hook)                                        ┃
┃  ──────────────────────────────────────                                        ┃
┃  "What should Claude do next?"                                                 ┃
┃  • Intercepts session end                                                      ┃
┃  • Injects RSSI template with guidance                                         ┃
┃  • Pivots to exploration if work remains                                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                                    │
                                    ∨
                                  ╭─────────────────────────────────────────╮
                                  │        Claude continues working         │
                                  ╰─────────────────────────────────────────╯
```

| Hook                       | When It Fires         | Purpose                    |
| -------------------------- | --------------------- | -------------------------- |
| `pretooluse-loop-guard.py` | Before tool execution | Block unauthorized stops   |
| `archive-plan.sh`          | Before plan edits     | Preserve work history      |
| `loop-until-done.py`       | On session stop       | Inject continuation prompt |

<details>
<summary>graph-easy source</summary>

```
graph { label: "Hook Coordination Sequence"; flow: south; }

[Claude wants to stop] { shape: rounded; }
[Claude continues working] { shape: rounded; }

[HOOK 1: pretooluse-loop-guard.py] { border: bold; }
[HOOK 2: archive-plan.sh] { border: bold; }
[HOOK 3: loop-until-done.py] { border: bold; }

[Claude wants to stop] -> [HOOK 1: pretooluse-loop-guard.py]
[HOOK 1: pretooluse-loop-guard.py] -- Before tool execution --> [HOOK 2: archive-plan.sh]
[HOOK 2: archive-plan.sh] -- Before plan edits --> [HOOK 3: loop-until-done.py]
[HOOK 3: loop-until-done.py] -- Injects RSSI --> [Claude continues working]
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

## Constraint Scanner (v3.0.0)

The constraint scanner detects environment restrictions that limit Ralph's freedom to refactor and explore. It runs during `/ralph:start` unless `--skip-constraint-scan` is provided.

```
        Constraint Scanning Flow

        ╭────────────────────────────╮
        │     /ralph:start           │
        ╰────────────────────────────╯
          │
          │ Step 1.5: Preset Confirmation
          ∨
        ╭────────────────────────────╮
        │   constraint-scanner.py    │
        ╰────────────────────────────╯
          │
          │ Dynamic worktree detection
          │ git rev-parse --git-common-dir
          ∨
        ┌────────────────────────────┐
        │    Scan Project Files      │
        └────────────────────────────┘
          │
          │ .claude/settings.json
          │ pyproject.toml
          ∨
        ┌────────────────────────────┐
        │   4-Tier Severity Filter   │
        └────────────────────────────┘
          │
          │ CRITICAL → Block start
          │ HIGH     → Escalate to user
          │ MEDIUM   → Deep-dive option
          │ LOW      → Log only
          ∨
        ╭────────────────────────────╮
        │   AskUserQuestion (3-panel)│
        ╰────────────────────────────╯
          │
          │ Panel 1: PROHIBIT
          │ Panel 2: ENCOURAGE
          │ Panel 3: CONTINUE?
          ∨
        ┌────────────────────────────┐
        │   ralph-config.json v3.0.0 │
        └────────────────────────────┘
          │
          │ guidance.forbidden[]
          │ guidance.encouraged[]
          ∨
        ╭────────────────────────────╮
        │       Step 2: Execution    │
        ╰────────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { flow: south; }

[/ralph:start] { shape: rounded; }
[/ralph:start] --> [constraint-scanner.py] { shape: rounded; }
[constraint-scanner.py] -- Dynamic worktree detection --> [Scan Project Files]
[Scan Project Files] -- .claude/settings.json, pyproject.toml --> [4-Tier Severity Filter]
[4-Tier Severity Filter] -- CRITICAL/HIGH/MEDIUM/LOW --> [AskUserQuestion (3-panel)] { shape: rounded; }
[AskUserQuestion (3-panel)] -- Panel 1: PROHIBIT, Panel 2: ENCOURAGE --> [ralph-config.json v3.0.0]
[ralph-config.json v3.0.0] -- guidance.forbidden[], guidance.encouraged[] --> [Step 2: Execution] { shape: rounded; }
```

</details>

### 4-Tier Severity System

> **Simple Version**: Not all problems are equally urgent. Think of it like a hospital triage — some issues need immediate attention, others can wait.

```
                    Constraint Severity Pyramid

                              ╱╲
                             ╱  ╲
                            ╱ ❌ ╲
                           ╱──────╲         CRITICAL: "Stop everything"
                          ╱        ╲        Can't start loop until fixed
                         ╱──────────╲
                        ╱     ⚠️     ╲
                       ╱──────────────╲     HIGH: "Ask user first"
                      ╱                ╲    User must acknowledge
                     ╱──────────────────╲
                    ╱        📋          ╲
                   ╱──────────────────────╲ MEDIUM: "Worth knowing"
                  ╱                        ╲ Shown if user wants details
                 ╱──────────────────────────╲
                ╱            📝              ╲
               ╱──────────────────────────────╲ LOW: "FYI"
              ╱                                ╲ Logged but doesn't interrupt
             ╱──────────────────────────────────╲
```

| Severity     | What It Means                        | Intended Action   | Implementation Status                                    | Real Example                    |
| ------------ | ------------------------------------ | ----------------- | -------------------------------------------------------- | ------------------------------- |
| **CRITICAL** | "This WILL break on another machine" | Block loop start  | ✅ `constraint-scanner.py:469` exit 2 → `start.md` exits | Your home path `/Users/terry/`  |
| **HIGH**     | "This MIGHT cause problems"          | Escalate to user  | ✅ Wired to AUQ pre-selection (v9.2.4+)                  | Someone else's path in config   |
| **MEDIUM**   | "Something to be aware of"           | Show in deep-dive | 📋 Designed, not yet wired                               | Dependency on local directories |
| **LOW**      | "Just noting this exists"            | Log only          | ✅ Saved to JSON, not displayed                          | Non-Ralph hook detected         |

**Decision Flow**:

1. **CRITICAL found?** → Block `/ralph:start` completely ✅
2. **HIGH found?** → Pre-select in forbidden AUQ (Step 1.6.2.5) ✅
3. **MEDIUM found?** → Offer "deep-dive" option (planned)
4. **LOW found?** → Log silently, proceed normally ✅

<details>
<summary>graph-easy source</summary>

```
graph { label: "Constraint Severity Pyramid"; flow: south; }

[CRITICAL] { border: double; }
[HIGH] { border: bold; }
[MEDIUM]
[LOW]

[Scan Project] -> [CRITICAL]
[CRITICAL] -- blocks --> [Stop Loop Start]
[CRITICAL] -- none --> [HIGH]
[HIGH] -- escalates --> [AskUserQuestion]
[HIGH] -- none --> [MEDIUM]
[MEDIUM] -- deep-dive --> [Show Details]
[MEDIUM] -- none --> [LOW]
[LOW] -- logs --> [Proceed]
```

</details>

### Key Files

- **Scanner**: `plugins/ralph/scripts/constraint-scanner.py`
- **Config Schema**: `plugins/ralph/hooks/core/config_schema.py` (v3.0.0 with Pydantic)
- **ADR**: `/docs/adr/2025-12-29-ralph-constraint-scanning.md`

---

## Stop Hook Guidance Persistence

> **Why guidance survives context compaction**: Claude's context window gets compacted over long sessions. The Stop hook reads `ralph-config.json` fresh from disk on **every iteration** (`loop-until-done.py:192-206`), then injects guidance into the RSSI template. This ensures Claude always sees forbidden/encouraged items, even after context truncation.

**Data Flow**:

```
          Guidance Persistence Mechanism

┌─────────────────┐     ┌───────────────────────────────────┐
│  /ralph:start   │ ──> │  User selects forbidden/encouraged │
└─────────────────┘     └───────────────────────────────────┘
                          │
                          │ Step 1.6.7: Write to disk
                          ∨
                        ┌───────────────────────────────────┐
                        │  .claude/ralph-config.json        │
                        │  guidance.forbidden[]             │
                        │  guidance.encouraged[]            │
                        └───────────────────────────────────┘
                          │
                          │ Every iteration...
                          ∨
┌─────────────────────────────────────────────────────────────┐
│  Stop Hook: loop-until-done.py                              │
│  ───────────────────────────                                │
│  1. Read ralph-config.json FRESH from disk (line 192-206)   │
│  2. Inject into rssi_context dict (line 207-237)            │
│  3. Render rssi-unified.md template (line 269-276)          │
│  4. Return JSON with guidance-embedded prompt               │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ decision: "block", reason: "<prompt>"
                          ∨
                        ┌───────────────────────────────────┐
                        │  Claude sees guidance in prompt   │
                        │  (even after context compaction)  │
                        └───────────────────────────────────┘
```

**Key Code Locations**:

| File                        | Lines   | Purpose                          |
| --------------------------- | ------- | -------------------------------- |
| `loop-until-done.py`        | 192-206 | Read guidance fresh from disk    |
| `loop-until-done.py`        | 207-237 | Build rssi_context with guidance |
| `template_loader.py`        | 285-296 | Extract forbidden/encouraged     |
| `templates/rssi-unified.md` | 30-61   | Render USER GUIDANCE section     |

---

## Holistic Plugin Wiring

> **Nothing dangles**: Every file in the Ralph plugin serves a purpose and is wired to other components. This diagram shows the complete spiderweb of connections.

```
                              Ralph Plugin Holistic Wiring

┌─────────────────────────────────────────────────────────────────────────────────┐
│ USER COMMANDS                                                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│ /ralph:start  ─┬─► constraint-scanner.py ─► .json ─┐                            │
│                └─► AUQ (Step 1.6.x) ─────────────────┼─► .claude/ralph-config.json
│ /ralph:forbid ────────────────────────────────────────┘                          │
│ /ralph:encourage ─────────────────────────────────────┘                          │
│ /ralph:stop ─────► .claude/STOP_LOOP (kill switch)                               │
│ /ralph:hooks ────► manage-hooks.sh ─► ~/.claude/settings.json                    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ∨
┌─────────────────────────────────────────────────────────────────────────────────┐
│ HOOKS (Registered in ~/.claude/settings.json)                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Stop: loop-until-done.py                                                         │
│   ├── Reads: .claude/ralph-config.json (guidance, limits)                       │
│   ├── Reads: ~/.claude/automation/loop-orchestrator/state/sessions/*.json       │
│   ├── Calls: template_loader.py → rssi-unified.md                               │
│   └── Returns: JSON with continuation prompt (guidance embedded)                 │
│                                                                                  │
│ PreToolUse (Write|Edit): archive-plan.sh                                        │
│   └── Archives plan files to ~/.claude/automation/.../archives/                 │
│                                                                                  │
│ PreToolUse (Bash): pretooluse-loop-guard.py                                     │
│   └── Blocks deletion of loop control files                                      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ∨
┌─────────────────────────────────────────────────────────────────────────────────┐
│ TEMPLATE RENDERING (Jinja2)                                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│ rssi-unified.md renders:                                                         │
│   - FORBIDDEN items (from guidance.forbidden[])                                  │
│   - ENCOURAGED items (from guidance.encouraged[])                                │
│   - OODA loop instructions                                                       │
│   - Iteration metrics (runtime, wall-clock, iteration count)                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ∨
┌─────────────────────────────────────────────────────────────────────────────────┐
│ CLAUDE'S PROMPT (Every Iteration)                                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Guidance appears here on EVERY iteration                                         │
│ (survives context compaction via fresh disk read)                                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Files That Must Exist**:

| Location                | File                         | Created By              | Read By              | Purpose           |
| ----------------------- | ---------------------------- | ----------------------- | -------------------- | ----------------- |
| `~/.claude/`            | `settings.json`              | `/ralph:hooks install`  | Claude Code startup  | Hook registration |
| `~/.claude/automation/` | `sessions/*.json`            | `loop-until-done.py`    | `loop-until-done.py` | Session state     |
| `~/.claude/automation/` | `rssi-evolution.json`        | `rssi_evolution.py`     | `loop-until-done.py` | Learned patterns  |
| `~/.claude/automation/` | `archives/*`                 | `archive-plan.sh`       | User analysis        | Plan backups      |
| `.claude/`              | `ralph-config.json`          | `/ralph:start`, AUQ     | `loop-until-done.py` | Config + guidance |
| `.claude/`              | `loop-enabled`               | `/ralph:start`          | `loop-until-done.py` | Loop active flag  |
| `.claude/`              | `STOP_LOOP`                  | `/ralph:stop`, user     | `loop-until-done.py` | Kill switch       |
| `.claude/`              | `ralph-constraint-scan.json` | `constraint-scanner.py` | Step 1.6.2.5 (AUQ)   | Scanner output    |

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

### Config Schema Hierarchy

> **Simple Version**: The config file has a clear structure — like nested boxes. Each box has specific settings inside it.

The configuration uses Pydantic v2 for validation (see `hooks/core/config_schema.py`):

```
                          Config Schema Hierarchy

┌─────────────────────────────────────────────────────────────────────────────┐
│  RalphConfig (root)                                                         │
│  ─────────────────                                                          │
│  The main configuration object, validated on every load                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────────────┐    ┌───────────────────────────────────┐ │
│  │  LoopLimitsConfig             │    │  GuidanceConfig                   │ │
│  │  ─────────────────            │    │  ──────────────                   │ │
│  │  min_hours: float = 9.0       │    │  forbidden: list[str] = []        │ │
│  │  max_hours: float = 999.0     │    │  encouraged: list[str] = []       │ │
│  │  min_iterations: int = 99     │    │                                   │ │
│  │  max_iterations: int = 999    │    │  Encourages OVERRIDE forbidden    │ │
│  └───────────────────────────────┘    └───────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────┐    ┌───────────────────────────────────┐ │
│  │  ConstraintScanConfig         │    │  GPUInfrastructureConfig          │ │
│  │  ─────────────────────        │    │  ──────────────────────           │ │
│  │  enabled: bool = True         │    │  available: bool = False          │ │
│  │  deep_dive: bool = False      │    │  host: str | None                 │ │
│  │  patterns: list[Pattern]      │    │  gpu: str | None                  │ │
│  └───────────────────────────────┘    └───────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Section                | Purpose                          | Key Fields                           |
| ---------------------- | -------------------------------- | ------------------------------------ |
| **loop_limits**        | When to allow stopping           | min/max hours, min/max iterations    |
| **guidance**           | What to work on (and avoid)      | forbidden[], encouraged[]            |
| **constraint_scan**    | Pre-start environment checks     | enabled, patterns[], severity levels |
| **gpu_infrastructure** | Remote GPU for heavy computation | host, gpu type, availability         |

<details>
<summary>graph-easy source</summary>

```
graph { label: "Config Schema Hierarchy"; flow: south; }

[RalphConfig] { border: double; }
[LoopLimitsConfig]
[GuidanceConfig]
[ConstraintScanConfig]
[GPUInfrastructureConfig]

[RalphConfig] -> [LoopLimitsConfig]
[RalphConfig] -> [GuidanceConfig]
[RalphConfig] -> [ConstraintScanConfig]
[RalphConfig] -> [GPUInfrastructureConfig]
```

</details>

### User Guidance (v8.7.0+)

The `guidance` section is rendered by the **unified RSSI template** (`rssi-unified.md`), which consolidated the previous dual-template architecture (implementation + exploration) into a single template.

**Key behavior**:

- Guidance appears in **ALL phases** (implementation and exploration)
- Uses Jinja2 `{% if task_complete %}` conditionals for phase-specific content
- Encouraged items **override** forbidden patterns
- Changes via `/ralph:encourage` and `/ralph:forbid` take effect on next iteration

**Kill Switch**: Create `.claude/STOP_LOOP` file to force stop immediately.

---

## Observability (v9.2.4+)

Ralph provides **dual-channel observability** so both humans and Claude can see what the hooks are doing.

```
                        Observability Channels

┌─────────────────────────────────────────────────────────────────────────┐
│                           Hook Operations                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │   Config Read   │  │  State Update   │  │ File Discovery  │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
│                              │                                           │
└──────────────────────────────┼───────────────────────────────────────────┘
                               │
                               ∨
                        ┌─────────────────────────────────────┐
                        │          emit(op, detail)           │
                        └─────────────────────────────────────┘
                               │
               ┌───────────────┴───────────────┐
               │                               │
               ∨                               ∨
        ┏━━━━━━━━━━━━━━━━━━━━━┓        ┌─────────────────────────────┐
        ┃   Terminal (stderr)  ┃        │     Claude (JSON reason)    │
        ┃  Users see instantly ┃        │  Via decision:block output  │
        ┗━━━━━━━━━━━━━━━━━━━━━━┛        └─────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Observability Channels"; flow: south; }

[Hook Operations] { shape: box; }
[Hook Operations] -> [emit(op, detail)]
[emit(op, detail)] -> [Terminal (stderr)] { border: bold; }
[emit(op, detail)] -> [Claude (JSON reason)]
```

</details>

### Channels

| Channel    | Target         | Mechanism                          | Visibility                 |
| ---------- | -------------- | ---------------------------------- | -------------------------- |
| **stderr** | Terminal (you) | `print(msg, file=sys.stderr)`      | Immediate, always visible  |
| **JSON**   | Claude         | `decision:block` with reason field | Claude sees in hook output |

### Observed Operations

| Operation     | When Emitted              | Example Message                                            |
| ------------- | ------------------------- | ---------------------------------------------------------- |
| `Config`      | Config file read          | `[ralph] [0.02s] Config: Loaded 3 forbidden, 2 encouraged` |
| `State`       | Session state loaded      | `[ralph] [0.05s] State: iteration 5, runtime 847s`         |
| `Discovery`   | File discovery complete   | `[ralph] [0.08s] Discovery: Found spec.md via transcript`  |
| `Adapter`     | Project adapter selected  | `[ralph] [0.10s] Adapter: Selected alpha-forge`            |
| `Convergence` | Adapter convergence check | `[ralph] [0.12s] Convergence: continue=true, conf=0.65`    |
| `Analysis`    | Loop detection check      | `[ralph] [0.15s] Analysis: Loop detected: 99%+ similar`    |
| `Backoff`     | Idle iteration backoff    | `[ralph] [0.18s] Backoff: Idle 3/5 (next wait: 30s)`       |
| `Template`    | RSSI template rendered    | `[ralph] [0.20s] Template: Rendering IMPLEMENTATION`       |
| `Archive`     | Plan file archived        | `[ralph] Archive: Saved plan.md to archives/`              |

### Key Files

- **Module**: `plugins/ralph/hooks/observability.py`
- **Instrumentation**: `loop-until-done.py`, `utils.py`, `template_loader.py`
- **Shell hooks**: `archive-plan.sh` (stderr only)

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
