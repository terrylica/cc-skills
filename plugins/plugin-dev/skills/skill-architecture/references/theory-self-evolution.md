**Skill**: [Skill Architecture](../SKILL.md)

# Theory: Self-Evolving Agent Skills

Synthesis of key concepts from [Gemini Deep Research #70](https://gemini.google.com/share/0f22b47e028d) — "The Autonomous Metacognitive Layer: Self-Evolving Agent Skills and the Protocol of Continuous Adaptation" (March 2026). Full report at `docs/research/gemini-self-evolving-skills.md`.

---

## Core Premise

Static `SKILL.md` files suffer from **instruction-environment impedance mismatch** — as APIs update, dependencies shift, and repository conventions mutate, static instructions silently degrade. Self-evolving skills close this gap by embedding metacognitive protocols that detect execution failures, trace root causes to their own instructions, and persist targeted fixes.

> "When I stopped asking 'will anyone read this' and started asking 'will this be true when I read it tomorrow,' the drift stopped." — OpenClaw community

---

## The Six Threads

### Thread 1: Self-Contained Evolution Protocols

Evolution protocols belong **inside** the skill file, not in external orchestrators. This ensures any agent invoking the skill automatically inherits the capacity to repair it.

**Key pattern**: Mark mutable sections with `[Evolvable]` tags. Correction protocols specify exact trigger conditions (execution errors, user corrections) and action sequences (isolate fault, verify against environment, targeted edit to evolvable sections only).

**Guardrail**: "No evolution without a `trigger_patterns` reference" — changes require empirical evidence, not speculation.

### Thread 2: Failure Detection and Anti-Pattern Recognition

A skill cannot evolve if it cannot distinguish between its own faults and environmental anomalies.

**Failure attribution model**:

1. Capture STDOUT/STDERR traces alongside the agent's prompt history
2. Cross-reference: did the agent execute exactly as the SKILL.md dictated?
3. If yes and the environment rejected it → high "Instruction Fault Probability"
4. If high-confidence output with zero empirical validation → "Confabulation Zone" alert

**Risk**: Over-aggressive attribution rewrites valid instructions during transient external failures (API outages, rate limits). The skill must distinguish **instruction faults** from **environmental faults**.

### Thread 3: Eval-Driven Feedback Loops

Binary assertions (pass/fail) are the mechanical ground truth for skill mutations. No "mostly good" — an assertion returns exactly true or false.

**`eval.json` companion pattern**:

- `regex_match`: output matches expected pattern
- `shell_execution`: command exits with expected code
- `line_count_limit`: output stays within bounds

**Mutation lifecycle**: Proposed mutation → temporary buffer → run against eval assertions → if all pass AND improve over baseline → commit to production. If any fail → destroy buffer, feed failure trace back.

**Risk (Goodhart's Law)**: Over-optimizing against static assertions strips nuanced, contextually valuable instructions that don't directly affect pass rate.

### Thread 4: Guardrails Against Skill Drift

Unrestricted self-evolution leads to **skill drift** — accumulated edits cause the skill to diverge from its original purpose.

**Mandatory pre-flight checks before any self-edit**:

1. **Scope boundary**: Edit confined to skill instructions, not application code
2. **Drift analysis**: Does this change the skill's primary objective? → REJECT
3. **Security degradation**: Does this remove safety constraints? → REJECT
4. **Value proposition**: Long-term systemic value, or temporary hack? → Temporary = REJECT

**Coverage-based abstraction levels** (OpenClaw `whtoo` model):

| Error Coverage | Abstraction Level | Permitted Action                                           |
| -------------- | ----------------- | ---------------------------------------------------------- |
| > 80%          | POLICY            | Adjust policy weights within existing logic                |
| 40-80%         | SUB_SKILL         | Generate dedicated sub-skill for the divergence            |
| < 40%          | PREDICATE         | Core logical restructuring (fundamental knowledge failure) |

### Thread 5: Real Implementations

| System                | Mechanism                                             | Measured Result                                         |
| --------------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| AutoResearchClaw      | 23-stage pipeline with "Failure to Lesson Conversion" | 24.8% reduction in stage retry rates                    |
| GEPA (Hermes)         | Genetic-Pareto Prompt Evolution with constraint gates | Surviving mutations auto-formatted as PRs               |
| OpenClaw `whtoo`      | Coverage-threshold transition rules                   | Three-tier abstraction control                          |
| Karpathy AutoResearch | Binary eval loop, TSV progress logging                | "Every improvement stacks. Every failure auto-reverts." |

**Key constraint**: Mutations must pass through Constraint Gates (test suites, 15KB size limit, semantic preservation checks) before merging.

### Thread 6: Docs-as-Autonomous-Code (Philosophy)

Self-evolving skills are the endgame of the docs-as-code movement. Static documentation cannot survive when "the knowledge half-life in AI has shrunk to months from years" (Deloitte Tech Trends 2026).

**Biological analogy** — three pillars of Darwinian evolution mapped to skills:

| Pillar             | System Equivalent               | Function                                              |
| ------------------ | ------------------------------- | ----------------------------------------------------- |
| Mutation           | LLM candidate generation        | Propose targeted edits to instructions                |
| Selection Pressure | Execution environment           | APIs, test suites, compilers that fail incorrect code |
| Fitness Criteria   | Binary assertions / `eval.json` | Mechanical loops determining which mutations survive  |

**Counterargument**: Autonomous self-modification may produce effective but incomprehensible skills — "liquid modernity" where the system works but no human understands why. Balance autonomy with human-reviewable evolution logs.

---

## How This Informs Our Implementation

| Gemini Concept                     | Our Implementation                                     | Location                     |
| ---------------------------------- | ------------------------------------------------------ | ---------------------------- |
| Self-contained evolution protocols | Post-Execution Reflection section (compulsory)         | SKILL.md                     |
| Failure attribution                | "Did MY instructions cause the failure?" in reflection | post-execution-reflection.md |
| Binary assertions (`eval.json`)    | Evolution-log with empirical evidence (lighter weight) | evolution-log.md             |
| Guardrails against drift           | "Only rectify based on observed empirical evidence"    | Anti-patterns table          |
| Coverage-based abstraction         | Not yet implemented (future: fragile skills registry)  | Planned                      |
| Semantic preservation              | Not yet implemented (future: diff-based review)        | Planned                      |

We deliberately chose a **lighter-weight** approach than full eval-driven loops. Our skills are human-authored with agent-assisted evolution, not fully autonomous. The Post-Execution Reflection pattern provides the structural feedback loop without the complexity of automated eval infrastructure.

---

## Sources

- **Primary**: [Gemini DR #70](https://gemini.google.com/share/0f22b47e028d) — full 20KB research report
- **Related**: [Gemini DR #69](https://gemini.google.com/share/274d0b18ba66) — skill-worthy knowledge taxonomy
- **Academic**: AutoSkill (ECNU-ICALK, Feb 2026), ArXiv 2602.20867v1 (security analysis)
- **Industry**: Deloitte Tech Trends 2026, MindStudio Blog (Karpathy AutoResearch applied to Claude Code)
- **Open Source**: [OpenClaw self-evolving-skill](https://github.com/openclaw/skills), [AutoResearchClaw](https://github.com/aiming-lab/AutoResearchClaw)
- **GitHub Issues**: [#67](https://github.com/terrylica/cc-skills/issues/67), [#68](https://github.com/terrylica/cc-skills/issues/68), [#69](https://github.com/terrylica/cc-skills/issues/69), [#70](https://github.com/terrylica/cc-skills/issues/70)
