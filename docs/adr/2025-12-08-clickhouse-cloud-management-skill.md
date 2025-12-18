---
status: accepted
date: 2025-12-08
decision-maker: Terry Li
consulted: [Explore-Agent, plugin-dev-skill-development]
research-method: single-agent
clarification-iterations: 3
perspectives: [EcosystemArtifact, LifecycleMigration]
---

# ADR: Extract ClickHouse Cloud Management Skill

**Design Spec**: [Implementation Spec](/docs/design/2025-12-08-clickhouse-cloud-management-skill/spec.md)

## Context and Problem Statement

The user memory file (`~/.claude/CLAUDE.md`) contains detailed ClickHouse Cloud management content including SQL user management, capability matrices, and password requirements. This inline content makes CLAUDE.md too large and violates the hub-and-spoke architecture pattern where the hub should contain only essential references, not detailed procedural knowledge.

The content needs to be extracted to a reusable skill in the `devops-tools` plugin within the `cc-skills` marketplace, following Anthropic's official skill development guidelines.

### Before/After

```
       ⏮️ Before: Inline Content

┌───────────────┐     ╭────────────────╮
│ Other Content │     │   CLAUDE.md    │
│               │ <── │  (~400 lines)  │
└───────────────┘     ╰────────────────╯
                        │
                        │
                        ∨
                      ┌────────────────┐
                      │ ClickHouse SQL │
                      │   Management   │
                      │  (~40 lines)   │
                      └────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Inline Content"; flow: south; }
[ CLAUDE.md\n(~400 lines) ] { shape: rounded; }
[ ClickHouse SQL\nManagement\n(~40 lines) ]
[ Other Content ]
[ CLAUDE.md\n(~400 lines) ] -> [ ClickHouse SQL\nManagement\n(~40 lines) ]
[ CLAUDE.md\n(~400 lines) ] -> [ Other Content ]
```

</details>

```
         ⏭️ After: Hub-and-Spoke

┌───────────────┐     ╭───────────────────╮
│ Other Content │     │     CLAUDE.md     │
│               │ <── │   (~350 lines)    │
└───────────────┘     ╰───────────────────╯
                        │
                        │
                        ∨
                      ┌───────────────────┐
                      │  Skill Reference  │
                      │     (1 line)      │
                      └───────────────────┘
                        │
                        │ invokes
                        ∨
                      ╔═══════════════════╗
                      ║   devops-tools:   ║
                      ║ clickhouse-cloud- ║
                      ║    management     ║
                      ╚═══════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Hub-and-Spoke"; flow: south; }
[ CLAUDE.md\n(~350 lines) ] { shape: rounded; }
[ Skill Reference\n(1 line) ]
[ Other Content ]
[ devops-tools:\nclickhouse-cloud-\nmanagement ] { border: double; }
[ CLAUDE.md\n(~350 lines) ] -> [ Skill Reference\n(1 line) ]
[ CLAUDE.md\n(~350 lines) ] -> [ Other Content ]
[ Skill Reference\n(1 line) ] -- invokes --> [ devops-tools:\nclickhouse-cloud-\nmanagement ]
```

</details>

## Research Summary

| Agent Perspective             | Key Finding                                                                                        | Confidence |
| ----------------------------- | -------------------------------------------------------------------------------------------------- | ---------- |
| Explore (cc-skills structure) | 16 plugins, 38 skills; devops-tools already has 5 skills                                           | High       |
| plugin-dev:skill-development  | Skills need third-person descriptions with trigger phrases, imperative body, 1500-2000 word target | High       |

## Decision Log

| Decision Area                | Options Evaluated                       | Chosen                 | Rationale                                                       |
| ---------------------------- | --------------------------------------- | ---------------------- | --------------------------------------------------------------- |
| Target plugin                | devops-tools, itp, new plugin           | devops-tools           | Already contains Doppler, MLflow - infrastructure tools pattern |
| Skill reference in CLAUDE.md | Path link, Name reference               | Name reference         | Skills installed from marketplace; paths won't work             |
| Content organization         | All in SKILL.md, Progressive disclosure | Progressive disclosure | Keep SKILL.md lean, SQL examples in references/                 |

### Trade-offs Accepted

| Trade-off                           | Choice      | Accepted Cost                                          |
| ----------------------------------- | ----------- | ------------------------------------------------------ |
| Hub simplicity vs. discoverability  | Simpler hub | User must know skill name to find detailed content     |
| Inline content vs. skill invocation | Skill       | Extra invocation step when needing ClickHouse guidance |

## Decision Drivers

- Hub-and-spoke architecture for user memory (CLAUDE.md as lean hub)
- Anthropic's skill development best practices (progressive disclosure)
- Skill marketplace installation pattern (skills referenced by name, not path)
- Existing devops-tools plugin with infrastructure management skills

## Considered Options

- **Option A**: Keep content inline in CLAUDE.md
- **Option B**: Create skill in devops-tools plugin with progressive disclosure
- **Option C**: Create standalone plugin for ClickHouse

## Decision Outcome

Chosen option: **Option B**, because:

1. devops-tools already contains infrastructure management skills (Doppler, MLflow)
2. Progressive disclosure keeps SKILL.md lean while detailed SQL goes to references/
3. Follows Anthropic's official skill development guidelines
4. Skill can be referenced by name (`devops-tools:clickhouse-cloud-management`)

## Synthesis

**Convergent findings**: All perspectives agreed on extracting to a skill, using devops-tools plugin, following progressive disclosure.

**Divergent findings**: Initial plan included path-based links which user corrected to name-based references.

**Resolution**: User clarified that marketplace skills must be referenced by name (e.g., `devops-tools:clickhouse-cloud-management`), not by file paths.

## Consequences

### Positive

- CLAUDE.md becomes leaner (target ~350 lines)
- ClickHouse content becomes reusable skill
- Follows marketplace skill patterns
- Progressive disclosure improves context management

### Negative

- Extra skill invocation step when needing ClickHouse guidance
- 1Password credential references remain in CLAUDE.md (credentials stay in hub)

## Architecture

```
                                    🏗️ Skill Architecture

╭────────────╮               ┏━━━━━━━━━━━━━━┓     ┌───────────────────┐     ┌─────────────────┐
│ ~/.claude/ │               ┃  cc-skills/  ┃     │ clickhouse-cloud- │     │   references/   │
│ CLAUDE.md  │  references   ┃   plugins/   ┃     │    management/    │     │ sql-patterns.md │
│            │ ────────────> ┃ devops-tools ┃ ──> │     SKILL.md      │ ──> │                 │
╰────────────╯               ┗━━━━━━━━━━━━━━┛     └───────────────────┘     └─────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Skill Architecture"; flow: east; }
[ ~/.claude/\nCLAUDE.md ] { shape: rounded; }
[ cc-skills/\nplugins/\ndevops-tools ] { border: bold; }
[ clickhouse-cloud-\nmanagement/\nSKILL.md ]
[ references/\nsql-patterns.md ]
[ ~/.claude/\nCLAUDE.md ] -- references --> [ cc-skills/\nplugins/\ndevops-tools ]
[ cc-skills/\nplugins/\ndevops-tools ] -> [ clickhouse-cloud-\nmanagement/\nSKILL.md ]
[ clickhouse-cloud-\nmanagement/\nSKILL.md ] -> [ references/\nsql-patterns.md ]
```

</details>

## References

- Anthropic's official skill development guidelines (external to this repository)
- [devops-tools plugin](/plugins/devops-tools/) - Target plugin location
