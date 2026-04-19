# crucible — Plugin Navigator

> Self-evolving research methodology. Transformation under pressure: weak hypotheses burn away, alloy-grade strategies emerge.

## What brings an agent here

You are investigating a quantitative (or any LLM-driven) research hypothesis and want to:

- Avoid known methodological traps (label leakage, wrong null, look-ahead, agent-z overstatement)
- Benefit from prior session experience distilled into reusable moves
- Preserve failed attempts without cluttering active work
- Record your own findings so future agents can inherit

## Genetic-evolutionary framing

This plugin treats research as a **genetic algorithm driven by large language models**:

| GA primitive    | Research analog                                                                         |
| --------------- | --------------------------------------------------------------------------------------- |
| Population      | Candidate hypotheses tested in parallel (by multi-lens agents)                          |
| Fitness         | Trade-weighted return + shuffled-null z + OOS replication + kill-selectivity            |
| Mutation        | Agent rephrases hypothesis with perturbation (tighter barrier, different filter)        |
| Crossover       | Combine two validated components (trigger × filter × management)                        |
| Selection       | Ledger `supersedes` DAG (explicit lineage of what replaced what)                        |
| Elitism         | Full-stack winner never discarded; kept as reference champion                           |
| Niching         | Asset-specific findings preserved as separate niches (e.g., EURUSD-only vs universal)   |
| Neutral drift   | Equivalent variants kept if simpler; no gratuitous churn                                |
| Lethal mutation | Fails all gates → moves to `d-emergent-resurrection/archive/` with resurrect conditions |

The "genome" is a **triple**: `(trigger, filter_cascade, trade_management_rule)`. Each component mutates independently; crossover recombines validated components.

## The 4 skills — when to invoke each

| Skill                                                                        | Trigger on user intent...                                                                   |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [00-navigator](./skills/00-navigator/SKILL.md)                               | "new research campaign", "how do I approach X?", "what should I know?"                      |
| [a-research-foundations](./skills/a-research-foundations/SKILL.md)           | "is this finding real?", "shuffled null", "significance", "causal feature", "label leakage" |
| [b-investigation-methodology](./skills/b-investigation-methodology/SKILL.md) | "test a hypothesis", "run a sweep", "multi-agent analysis", "gate validation"               |
| [c-meta-governance](./skills/c-meta-governance/SKILL.md)                     | "should we pivot?", "ship this?", "kill or refine?", "context budget", "supersede"          |
| [d-emergent-resurrection](./skills/d-emergent-resurrection/SKILL.md)         | "review dormant ideas", "what's archived?", "resurrect failed attempt", "can X come back?"  |

## The 18 universal principles (distributed across 4 skills)

**Skill A — Research Foundations** (epistemic layer):

1. causal-feature-invariant (bars[:i])
2. label-leakage-bar-local-scaling
3. shuffled-null-design (3 null types)
4. agent-significance-corrections
5. record-keeping-discipline
6. post-mortem-before-abandon

**Skill B — Investigation Methodology** (execution layer):

1. llm-native-data-representation (quintile tokens)
2. serial-adversarial-gates (A/B/C/D/E protocol)
3. multi-lens-agent-synthesis
4. per-trade-enrichment-postmortem
5. agnostic-null-cascade (orthogonal null retest)
6. compute-orchestration-pueue

**Skill C — Meta-governance** (decision layer):

1. physical-constraint-first-pivot
2. incremental-artifact-promotion
3. gate-failure-scopes-not-kills
4. agent-lens-disagreement-as-signal
5. context-budget-discipline
6. supersede-not-rewrite

**Skill D — Emergent Resurrection** (archive + exhumation):

- Failure-mode taxonomy
- `resurrect_if:` frontmatter schema
- 3-layer exhumation gate (autonomous flag → agent review → human sign-off)

## Reading order

New agents starting a research campaign: A → B → C (concurrent with B) → D (as needed for archived hypotheses).

Single-principle lookup: use the skill's trigger phrase, or grep individual principle files in `skills/<skill>/references/`.

## Self-evolution

This plugin is **not finalized**. Every skill has `references/evolution-log.md` (append-only) + a **Post-Execution Reflection** section at the end. Guardrails:

- Updates require an evidence link (to a ledger entry or audit folder)
- `confirmation_count` tracks independent re-validation of each principle (higher = more trustworthy)
- Demoted principles move to `references/archive/` with `superseded_by` and `resurrect_if` fields
- Plugin-level changes are appended to `docs/evolution/plugin-evolution.jsonl`

## Cross-plugin

- Original methodology files: `findings/methodology/` (the 10 original principles)
- Campaign ledger: `findings/evolution/evolution.jsonl`
- Audit folder index: `findings/evolution/audits/CLAUDE.md`

## Anti-patterns (don't do)

1. Treat principles as "proven universal" from N=1 evidence — they are strength-ranked
2. Auto-apply a skill's guidance without checking its `confirmation_count`
3. Delete failed content — move to `archive/` with resurrect conditions
4. Spawn this plugin for non-research tasks (plumbing, refactoring, etc.)
5. Ignore the **Post-Execution Reflection** footer — that's the self-evolution entry point
