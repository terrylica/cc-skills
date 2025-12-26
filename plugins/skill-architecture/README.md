# Skill Architecture Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![References](https://img.shields.io/badge/References-12-blue.svg)]()
[![Scripts](https://img.shields.io/badge/Scripts-3-green.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Meta-skill for creating effective Claude Code skills with TodoWrite templates, security practices, and structural patterns.

> [!NOTE]
> **Scope**: Claude Code CLI Agent Skills (`~/.claude/skills/`), not Claude.ai API skills

## Features

- **5 TodoWrite Templates**: Pre-defined task lists for Create, Update, Add Resources, Convert to Self-Evolving, and Troubleshoot workflows
- **Continuous Improvement**: Proactive self-evolution triggers—skills upgrade themselves when insights emerge
- **Progressive Disclosure**: 3-level context management (metadata → SKILL.md → references)
- **Security Practices**: `allowed-tools` restrictions with CVE references
- **Structural Patterns**: Workflow, Task, Reference, and Capabilities patterns
- **Validation Scripts**: `quick_validate.py` for local development, `package_skill.py` for distribution

## How It Works

Skills are modular packages that extend Claude's capabilities with specialized knowledge, workflows, and tools. This meta-skill provides the architecture for creating them.

### Progressive Disclosure (3 Levels)

```
📚 Progressive Disclosure (3 Levels)

      ┌────────────────────────┐
      │   Level 1: Metadata    │
      │  (name + description)  │
      │       ~100 words       │
      └────────────────────────┘
        │
        │
        ∨
      ┌────────────────────────┐
      │ Level 2: SKILL.md Body │
      │ (when skill triggers)  │
      │       <5k words        │
      └────────────────────────┘
        │
        │
        ∨
      ┌────────────────────────┐
      │  Level 3: References   │
      │      (as needed)       │
      │       unlimited        │
      └────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "📚 Progressive Disclosure (3 Levels)"; flow: south; }
[ L1 ] { label: "Level 1: Metadata\n(name + description)\n~100 words"; }
[ L2 ] { label: "Level 2: SKILL.md Body\n(when skill triggers)\n<5k words"; }
[ L3 ] { label: "Level 3: References\n(as needed)\nunlimited"; }
[ L1 ] --> [ L2 ] --> [ L3 ]
```

</details>

### Skill Creation Workflow (6 Steps)

```
                                    🔧 Skill Creation Workflow (6 Steps)

╭───────────────╮     ┌───────────┐     ┌─────────┐     ┌──────────┐     ┌─────────────┐     ╔═════════════╗
│ 1. Understand │     │  2. Plan  │     │ 3. Init │     │ 4. Edit  │     │ 5. Validate │     ║ 6. Register ║
│   Examples    │ ──> │ Resources │ ──> │ Script  │ ──> │ SKILL.md │ ──> │             │ ──> ║  & Iterate  ║
╰───────────────╯     └───────────┘     └─────────┘     └──────────┘     └─────────────┘     ╚═════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔧 Skill Creation Workflow (6 Steps)"; flow: east; }
[ S1 ] { shape: rounded; label: "1. Understand\nExamples"; }
[ S2 ] { label: "2. Plan\nResources"; }
[ S3 ] { label: "3. Init\nScript"; }
[ S4 ] { label: "4. Edit\nSKILL.md"; }
[ S5 ] { label: "5. Validate"; }
[ S6 ] { border: double; label: "6. Register\n& Iterate"; }
[ S1 ] -> [ S2 ] -> [ S3 ] -> [ S4 ] -> [ S5 ] -> [ S6 ]
```

</details>

### Skill Anatomy

```
📁 Skill Anatomy

                    ┌─────────────┐
                    │  scripts/   │
                    │ (Optional)  │
                    └─────────────┘
                      ∧
                      │
                      │
┌─────────────┐     ┌─────────────┐     ┌────────────┐
│ references/ │     │ skill-name/ │     │  SKILL.md  │
│ (Optional)  │ <── │             │ ──> │ (Required) │
└─────────────┘     └─────────────┘     └────────────┘
                      │
                      │
                      ∨
                    ┌─────────────┐
                    │   assets/   │
                    │ (Optional)  │
                    └─────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "📁 Skill Anatomy"; flow: south; }
[ Root ] { label: "skill-name/"; }
[ SKILL ] { label: "SKILL.md\n(Required)"; }
[ Scripts ] { label: "scripts/\n(Optional)"; }
[ Refs ] { label: "references/\n(Optional)"; }
[ Assets ] { label: "assets/\n(Optional)"; }
[ Root ] --> [ SKILL ]
[ Root ] --> [ Scripts ]
[ Root ] --> [ Refs ]
[ Root ] --> [ Assets ]
```

</details>

## Installation

### Option 1: Plugin Installation (Recommended)

```bash
# 1. Add marketplace
/plugin marketplace add terrylica/cc-skills

# 2. Install plugin
/plugin install cc-skills@skill-architecture

# 3. Use skill
# Triggered automatically when creating or modifying skills
```

### Option 2: Settings Configuration

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "cc-skills": {
      "source": {
        "source": "github",
        "repo": "terrylica/cc-skills"
      }
    }
  }
}
```

### Option 3: Manual Installation

```bash
# 1. Clone repo
git clone git@github.com:terrylica/cc-skills.git /tmp/cc-skills

# 2. Copy skill
cp -r /tmp/cc-skills/plugins/skill-architecture ~/.claude/skills/
```

## Usage

### TodoWrite Templates

The skill provides 5 pre-defined templates for common skill workflows:

| Template                        | Purpose                                              |
| ------------------------------- | ---------------------------------------------------- |
| **A: Create New Skill**         | 11-step workflow for new skills                      |
| **B: Update Existing Skill**    | 8-step workflow for modifications                    |
| **C: Add Resources**            | 7-step workflow for adding scripts/references/assets |
| **D: Convert to Self-Evolving** | 9-step workflow for adding self-maintenance          |
| **E: Troubleshoot**             | 7-step workflow for debugging triggers               |

### Quick Commands

```bash
# Initialize new skill
~/.claude/plugins/marketplaces/anthropic-agent-skills/skill-creator/scripts/init_skill.py my-skill --path ~/.claude/skills/

# Validate skill (local development)
~/.claude/plugins/marketplaces/anthropic-agent-skills/skill-creator/scripts/quick_validate.py ~/.claude/skills/my-skill/

# Package skill (distribution)
~/.claude/plugins/marketplaces/anthropic-agent-skills/skill-creator/scripts/package_skill.py ~/.claude/skills/my-skill/
```

### Skill Quality Checklist

After any skill work, verify:

- [ ] YAML frontmatter valid (name lowercase-hyphen, description has triggers)
- [ ] Description includes WHEN to use (trigger keywords)
- [ ] TodoWrite templates cover all common scenarios
- [ ] Post-Change Checklist included for self-maintenance
- [ ] Project CLAUDE.md updated if new/renamed skill
- [ ] Validated with `quick_validate.py`

## Reference Files

| File                                                                                          | Purpose                                                                 |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [`structural-patterns.md`](skills/skill-architecture/references/structural-patterns.md)       | 4 skill architecture patterns (Workflow, Task, Reference, Capabilities) |
| [`workflow-patterns.md`](skills/skill-architecture/references/workflow-patterns.md)           | Workflow skill implementation patterns                                  |
| [`progressive-disclosure.md`](skills/skill-architecture/references/progressive-disclosure.md) | Context management and 3-level loading                                  |
| [`creation-workflow.md`](skills/skill-architecture/references/creation-workflow.md)           | Step-by-step skill creation process                                     |
| [`scripts-reference.md`](skills/skill-architecture/references/scripts-reference.md)           | Marketplace script usage                                                |
| [`security-practices.md`](skills/skill-architecture/references/security-practices.md)         | Threats, defenses, and CVE references                                   |
| [`token-efficiency.md`](skills/skill-architecture/references/token-efficiency.md)             | Context optimization strategies                                         |
| [`advanced-topics.md`](skills/skill-architecture/references/advanced-topics.md)               | CLI vs API, composition, known bugs                                     |
| [`validation-reference.md`](skills/skill-architecture/references/validation-reference.md)     | Quality checklist and validation                                        |
| [`bash-compatibility.md`](skills/skill-architecture/references/bash-compatibility.md)         | Bash/zsh compatibility patterns for macOS                               |
| [`SYNC-TRACKING.md`](skills/skill-architecture/references/SYNC-TRACKING.md)                   | Marketplace version tracking                                            |
| [`evolution-log.md`](skills/skill-architecture/references/evolution-log.md)                   | This skill's change history                                             |

## Troubleshooting

### Skill not triggering

1. Check YAML frontmatter syntax (no colons in description)
2. Verify trigger keywords in description match user queries
3. Check skill location (`~/.claude/skills/` or project `.claude/skills/`)
4. Validate with `quick_validate.py`
5. Test with explicit trigger phrase

### YAML description breaks

```yaml
# ❌ BREAKS - colon parsed as YAML key:value
description: ...CRITICAL: requires flag

# ✅ WORKS - dash instead of colon
description: ...CRITICAL - requires flag
```

### Validation errors

```bash
# Run quick validation
~/.claude/plugins/marketplaces/anthropic-agent-skills/skill-creator/scripts/quick_validate.py <path/to/skill>
```

Common issues:

- Missing YAML frontmatter
- Name not lowercase-hyphen format
- Description exceeds 1024 characters

## License

MIT
