# SOTA provenance map

Every non-obvious mechanism in this plugin, its source, and where it is implemented. Kept so future maintainers know which parts are load-bearing research results vs. house convention.

| Mechanism | Source | Implemented at |
|---|---|---|
| 3-stage council skeleton (parallel first opinions → anonymized peer review → chairman synthesis) | [karpathy/llm-council](https://github.com/karpathy/llm-council) (`backend/council.py`) | Overall pipeline shape; anonymization side-table mirrors its `label_to_model` map |
| Anonymized peer review (judges must not know authorship) | Self-preference bias in LLM-as-a-judge, [arXiv:2410.21819](https://arxiv.org/abs/2410.21819) | PUBLIC_FIELDS whitelist ([schemas.md](./schemas.md)); provenance side-table |
| Position swapping / order-bias control | Judge-bias benchmark "Judging the Judges", [arXiv:2604.23178](https://arxiv.org/abs/2604.23178) (position bias ≈10–15 pt swing) | Per-skeptic seeded permutation + PROSECUTE/DEFEND framing split |
| Refute-first adversarial gate; quorum-kill; plausibility ≠ correctness (80+ agents endorsed a nonexistent OpenSSL bug; curl bounty <5% confirmed) | Refute-or-Promote, [arXiv:2604.19049](https://arxiv.org/pdf/2604.19049) | Skeptic stage: mandatory `strongest_refutation`; kill = ⌈2S/3⌉ + cross-framing majority |
| Evidence ladder; PoC-or-it-didn't-happen | AnyPoC, [arXiv:2604.11950](https://arxiv.org/abs/2604.11950) | [evidence-ladder.md](./evidence-ladder.md); tribunal stage |
| Hierarchical fault localization (file → element → line); repro-test patch validation | Agentless, [arXiv:2407.01489](https://arxiv.org/abs/2407.01489) (FSE 2025) | Context-pack index; decomposition lens; repro-as-fix-acceptance |
| Runtime-state grounding beats self-reflection for debugging | LDB "Debug like a Human", [arXiv:2402.16906](https://arxiv.org/abs/2402.16906) | `runtime-trace` evidence rung; debug-mode experiments |
| Critics out-find humans but hallucinate bugs → precision dial required | CriticGPT "LLM Critics Help Catch LLM Bugs", [arXiv:2407.00215](https://arxiv.org/abs/2407.00215) | CONFIRMED/PLAUSIBLE split; only CONFIRMED auto-fixed |
| Diverse reasoning stances > same-model resampling | Mixture-of-Agents, [arXiv:2406.04692](https://arxiv.org/abs/2406.04692) (ICLR 2025); Diversity of Thought MAD, [arXiv:2410.12853](https://arxiv.org/html/2410.12853v1) | [lenses.md](./lenses.md): 6 stances × model tiers |
| Free-form multi-round debate often fails to beat CoT+self-consistency; deliberation homogenizes | MAD critique, [arXiv:2502.08788](https://arxiv.org/html/2502.08788v2); Deliberative Illusion, [arXiv:2606.03032](https://arxiv.org/pdf/2606.03032) | Design decision: structured stages, NO free agent chat |
| Rationale-based synthesis beats label-only voting | LLMs-as-Judges survey, [arXiv:2412.05579](https://arxiv.org/pdf/2412.05579) | Chairman rule in [report-template.md](./report-template.md) |
| Goal → hard/soft invariant decomposition; decoupled verifier | U-Define, [arXiv:2605.02765](https://arxiv.org/pdf/2605.02765); PI-Level review, [arXiv:2604.04089](https://arxiv.org/pdf/2604.04089) | P1 invariant stage; goal-audit dual decomposition |
| Orchestrator-worker economics: scale fleet to task, token budget dominates | Anthropic multi-agent research system, [engineering post](https://www.anthropic.com/engineering/multi-agent-research-system) | Fleet auto-sizing; phase budget ceilings with graceful degradation |
| Falsifiable-prediction hypothesis elimination; skeptic always included; map-the-disagreement (don't vote-override); supersede-not-rewrite; negative knowledge as deliverable | crucible plugin (house), `plugins/crucible/skills/{a,b,c,d}` | HYPOTHESIS schema; contested→disagreement-mapper; refuted appendix; debug elimination table |
| Multi-perspective finding validation (Intent/Integration/History) | dead-code-detector (house), `plugins/quality-tools/skills/dead-code-detector/SKILL.md:191-268` | Ancestor of the dependency-graph lens + skeptic panel |
| Static tool arsenal with graceful degradation; boundary anti-pattern catalog; Evidence/Root-Cause/Fix/Verification report blocks | pre-ship-review + multi-agent-e2e-validation (house), `plugins/quality-tools/` | static-arsenal lens; spec-conformance checklist; report finding blocks |

## Design decisions that consciously deviate from a source

- **Karpathy's chairman is a council member LLM; ours is the main session** — it has repo, conversation, and goal context his context-free chairman lacks.
- **Karpathy ranks answers; we gate findings on execution evidence** — ranking measures persuasiveness, which the Refute-or-Promote failure case shows is insufficient for code.
- **Crucible forbids voting; Karpathy aggregates ranks. We hybridize**: quorum kills only (cheap noise filter); survivors with skeptic splits get disagreement-mapping, and execution evidence — not majority — settles them.
