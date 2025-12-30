---
status: accepted
date: 2025-12-20
decision-maker: Terry Li
consulted: [Explore-Agent]
research-method: single-agent
clarification-iterations: 3
perspectives: [SystemArchitecture, PerformanceOptimization, UserExperience]
---

# ADR: Ralph Eternal Loop Architecture

> **Note**: Ralph is an autonomous improvement engine for Alpha Forge. The eternal loop behavior ensures continuous work discovery and execution.

**Design Spec**: [Implementation Spec](/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md)

## Context and Problem Statement

When Ralph operates in no-focus autonomous mode, it goes "idle" instead of actively exploring for improvements. The root cause is that `scan_work_opportunities()` returns an empty list when all automated checks pass, and the exploration template's Jinja2 conditional hides the opportunities section, leaving Claude with no concrete work items.

A static fallback list is insufficient for true recursive self-improvement behavior. Ralph requires:

1. Dynamic capability discovery (use whatever tools exist)
2. Session history mining (learn from past explorations)
3. Self-modification (improve discovery mechanisms)
4. Meta-improvement (improve how it improves)
5. Web-powered feature discovery (search for domain-aligned big features)
6. SOTA quality gates (ensure solutions use state-of-the-art approaches)

### Before/After

**Before: Ralph Idle Behavior**

```
                   ⏮️ Before: Ralph Idle Behavior

┌─────────────┐     ╭───────────────────────────╮     ┌──────────────┐
│ README gaps │ <── │ scan_work_opportunities() │ ──> │ lychee check │
└─────────────┘     ╰───────────────────────────╯     └──────────────┘
  │                   │                                 │
  │                   │                                 │
  │                   ∨                                 │
  │                 ┌───────────────────────────┐       │
  │                 │         ADR gaps          │       │
  │                 └───────────────────────────┘       │
  │                   │                                 │
  │                   │                                 │
  │                   ∨                                 │
  │                 ╔═══════════════════════════╗       │
  └───────────────> ║        Empty List         ║ <─────┘
                    ╚═══════════════════════════╝
                      │
                      │
                      ∨
                    ┌───────────────────────────┐
                    │  Template hides section   │
                    └───────────────────────────┘
                      │
                      │
                      ∨
                    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
                    ┃     Claude goes IDLE      ┃
                    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Ralph Idle Behavior"; flow: south; }
[ scan_work_opportunities() ] { shape: rounded; }
[ scan_work_opportunities() ] -> [ lychee check ]
[ scan_work_opportunities() ] -> [ README gaps ]
[ scan_work_opportunities() ] -> [ ADR gaps ]
[ lychee check ] -> [ Empty List ]
[ README gaps ] -> [ Empty List ]
[ ADR gaps ] -> [ Empty List ]
[ Empty List ] { border: double; }
[ Empty List ] -> [ Template hides section ]
[ Template hides section ] -> [ Claude goes IDLE ] { border: bold; }
```

</details>

**After: Ralph Eternal Loop**

```
   ⏭️ After: Ralph Eternal Loop

╭────────────────────────────╮
│ Level 2: Dynamic Discovery │ <┐
╰────────────────────────────╯  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│  Level 3: History Mining   │  │
└────────────────────────────┘  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│ Level 4: Self-Modification │  │
└────────────────────────────┘  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│  Level 5: Meta-Improvement │  │
└────────────────────────────┘  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│   Level 6: Web Discovery   │  │
└────────────────────────────┘  │
  │                             │
  │                             │
  ∨                             │
╔════════════════════════════╗  │
║        Quality Gate        ║  │
╚════════════════════════════╝  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│  Execute Best Opportunity  │  │
└────────────────────────────┘  │
  │                             │
  │                             │
  ∨                             │
┌────────────────────────────┐  │
│    Accumulate Knowledge    │ ─┘
└────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Ralph Eternal Loop"; flow: south; }
[ Level 2: Dynamic Discovery ] { shape: rounded; }
[ Level 2: Dynamic Discovery ] -> [ Level 3: History Mining ]
[ Level 3: History Mining ] -> [ Level 4: Self-Modification ]
[ Level 4: Self-Modification ] -> [ Level 5: Meta-Improvement ]
[ Level 5: Meta-Improvement ] -> [ Level 6: Web Discovery ]
[ Level 6: Web Discovery ] -> [ Quality Gate ] { border: double; }
[ Quality Gate ] -> [ Execute Best Opportunity ]
[ Execute Best Opportunity ] -> [ Accumulate Knowledge ]
[ Accumulate Knowledge ] -> [ Level 2: Dynamic Discovery ]
```

</details>

## Research Summary

| Agent Perspective | Key Finding                                                                                                     | Confidence |
| ----------------- | --------------------------------------------------------------------------------------------------------------- | ---------- |
| Explore-Agent     | Ralph has session history infrastructure (`recent_outputs`, `metrics_history`) but doesn't mine it for patterns | High       |
| Explore-Agent     | `scan_work_opportunities()` only checks lychee, README gaps, ADR gaps - returns empty too often                 | High       |
| Explore-Agent     | Adapter architecture exists for project-specific behavior but no learning/evolution mechanism                   | High       |
| Explore-Agent     | Template system uses Jinja2 but conditionally hides opportunities when list is empty                            | High       |

## Decision Log

| Decision Area              | Options Evaluated                                      | Chosen           | Rationale                                                     |
| -------------------------- | ------------------------------------------------------ | ---------------- | ------------------------------------------------------------- |
| Discovery Depth            | Level 2 only, Levels 2-3, Levels 2-4, All levels (2-6) | All levels (2-6) | Full discovery stack with web discovery for big features      |
| Exploration Aggressiveness | Conservative, Balanced, Proactive                      | Proactive        | User chose "never idle" - always find work                    |
| Quality Gate               | None, Basic, SOTA-enforced                             | SOTA-enforced    | All solutions must use SOTA concepts or well-maintained OSS   |
| Loop Behavior              | Single-pass, Fixed iterations, Eternal                 | Eternal          | Ralph loops forever, accumulating knowledge across iterations |

### Trade-offs Accepted

| Trade-off                | Choice                | Accepted Cost                                            |
| ------------------------ | --------------------- | -------------------------------------------------------- |
| Complexity vs Simplicity | Full Ralph stack      | More modules to maintain, higher cognitive load          |
| Autonomy vs Control      | Eternal loop          | Requires explicit stop mechanism                         |
| Web Search vs Local-only | Web-powered discovery | Depends on network, potential for irrelevant suggestions |

## Decision Drivers

- User explicitly stated Ralph is "wrong" for going idle
- Ralph should never idle - it finds or creates improvement opportunities
- Knowledge should accumulate across loop iterations
- Solutions must meet SOTA/well-maintained OSS quality standards

## Considered Options

- **Option A**: Static Fallback List - Hard-coded checks that always run
- **Option B**: Dynamic Discovery Only (Level 2) - Scan for available tools, use them
- **Option C**: Full Ralph Stack (Levels 2-6) - Dynamic discovery + history mining + self-modification + meta-improvement + web discovery + quality gates + eternal loop <- Selected

## Decision Outcome

Chosen option: **Option C (Full Ralph Stack)**, because:

1. User explicitly requested "all levels (2-5)" plus web search for big features
2. Static fallback doesn't learn or evolve
3. True recursive self-improvement requires the loop to never terminate
4. Knowledge accumulation across iterations enables smarter discovery over time
5. SOTA quality gates ensure improvements are high-quality

## Synthesis

**Convergent findings**: Ralph's existing infrastructure (session state, adapter architecture, template system) provides building blocks for recursive self-improvement, but lacks learning/evolution mechanisms.

**Divergent findings**: None - single agent exploration with clear root cause identification.

**Resolution**: Build on existing infrastructure, add 5 new Ralph modules, update templates for eternal loop awareness.

## Consequences

### Positive

- Ralph never idles - always finds or creates improvement opportunities
- Knowledge accumulates across iterations, improving discovery quality
- Web search discovers domain-aligned big features
- SOTA quality gates ensure high-quality improvements
- Self-modification allows discovery mechanism to evolve

### Negative

- Increased complexity (5 new modules)
- Eternal loop requires explicit stop mechanism
- Web search depends on network availability
- Learning takes time to accumulate meaningful patterns

## Architecture

```
                                              🏗️ Ralph Architecture

┏━━━━━━━━━━━━━━━┓      ┌───────────────┐     ┌──────────┐     ┌─────────┐     ╔══════════════╗     ┌─────────────┐
┃     State     ┃      │ L4: Evolution │     │ L5: Meta │     │ L6: Web │     ║ Orchestrator ║     │ Loop Driver │
┃  Persistence  ┃ <──> │               │ ──> │          │ ──> │         │ ──> ║              ║ ──> │             │
┗━━━━━━━━━━━━━━━┛      └───────────────┘     └──────────┘     └─────────┘     ╚══════════════╝     └─────────────┘
                         ∧
                         │
                         │
╭───────────────╮      ┌───────────────┐
│ L2: Discovery │ ───> │  L3: History  │
╰───────────────╯      └───────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Ralph Architecture"; flow: east; }

[ ralph_discovery.py ] { label: "L2: Discovery"; shape: rounded; }
[ ralph_history.py ] { label: "L3: History"; }
[ ralph_evolution.py ] { label: "L4: Evolution"; }
[ ralph_meta.py ] { label: "L5: Meta"; }
[ ralph_web_discovery.py ] { label: "L6: Web"; }

[ discovery.py ] { label: "Orchestrator"; border: double; }
[ loop-until-done.py ] { label: "Loop Driver"; }
[ RalphKnowledge ] { label: "State\nPersistence"; border: bold; }

[ ralph_discovery.py ] -> [ ralph_history.py ] -> [ ralph_evolution.py ] -> [ ralph_meta.py ] -> [ ralph_web_discovery.py ]
[ ralph_web_discovery.py ] -> [ discovery.py ]
[ discovery.py ] -> [ loop-until-done.py ]
[ RalphKnowledge ] <-> [ ralph_evolution.py ]
```

</details>

## References

- [Ralph README](/plugins/ralph/README.md)
