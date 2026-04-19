# crucible

> Self-evolving research methodology for LLM-driven strategy discovery. Where weak hypotheses burn away and alloy-grade strategies emerge.

A Claude Code plugin for **emergent, incremental, genetic-evolutionary research** — applied to quantitative strategy discovery but agnostic to domain.

## What this plugin is

A codified set of **universal research principles** distilled from a successful multi-day investigation that produced one validated positive finding (`NGRAM3FU-STRADDLE-001-FULL-STACK`) after 17 falsified hypotheses. The principles cover how to:

- Encode data for LLM observation (quintile tokens, bar-local scaling)
- Choose the right adversarial null for a given hypothesis
- Run multi-lens agent synthesis with parallel specialists
- Layer serial validation gates (A/B/C/D/E) before trust
- Preserve failed attempts so they can re-emerge when conditions change
- Record findings in an append-only ledger with supersedes links
- Self-evolve: skills update themselves when reality diverges

## What this plugin is NOT

- Not a quant library (no financial formulas, no backtest engine)
- Not a one-shot tutorial (principles are reference, not walkthrough)
- Not "approved forever" — each principle is strength-ranked; weak ones can be demoted

## Skills

| Skill                                                                        | When to use                                                            |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| [00-navigator](./skills/00-navigator/SKILL.md)                               | New research campaign — read this first                                |
| [a-research-foundations](./skills/a-research-foundations/SKILL.md)           | Before claiming any positive finding — 6 epistemic disciplines         |
| [b-investigation-methodology](./skills/b-investigation-methodology/SKILL.md) | During hypothesis exploration — 6 execution patterns                   |
| [c-meta-governance](./skills/c-meta-governance/SKILL.md)                     | When deciding whether to pivot, persist, or ship — 6 decision patterns |
| [d-emergent-resurrection](./skills/d-emergent-resurrection/SKILL.md)         | When reviewing dormant/failed hypotheses for possible resurrection     |

## Installation (for this project)

This plugin is project-local. It auto-loads when an agent operates in `/Users/<you>/eon/research-lab-repo/`. The project's root `CLAUDE.md` contains backlinks to it.

To promote to the global marketplace later:

```bash
# Move plugin to cc-skills marketplace
cp -r plugins/crucible ~/.claude/plugins/marketplaces/cc-skills/plugins/
claude plugin install crucible@cc-skills
```

## Self-evolution

Every skill ends with a **Post-Execution Reflection** section. When a skill is invoked and its guidance produces a poor result (or a better pattern emerges), the agent is explicitly authorized to update the skill in-place AND append to `docs/evolution/plugin-evolution.jsonl`.

Guardrails against entropy:

1. Updates require evidence (ledger entry linking to the observation that motivated the change)
2. No deletions — deprecated content moves to `references/archive/` with a `superseded_by` pointer
3. Strength ranking — each principle carries a `confirmation_count` that grows when independent evidence re-validates it
4. Resurrection is possible — failed content can move from `archive/` back to active if conditions specified at archival time are met

## Provenance

Distilled from session `ca9d7ffa-ef5a-41d0-94c8-56f113a132f2` (2026-04-18 to 2026-04-19, 376 user turns, 67 MB JSONL). Full arc preserved at `findings/evolution/audits/2026-04-19-ngram3fu-straddle/CHRONICLE.md`.

## Related

- Project repo: [research-lab-repo](https://github.com/terrylica/research-lab-repo)
- Source methodology files: `findings/methodology/` (the 10 original principles, pre-plugin)
- Ledger: `findings/evolution/evolution.jsonl` (5-entry supersedes chain for NGRAM3FU-STRADDLE-001)

## License

MIT.
