**Skill**: [Skill Architecture](../SKILL.md)

# Skill Creation Process (Detailed Tutorial)

> **Note**: Use [Task Templates](./task-templates.md) for execution. This section provides detailed context for each phase.

## Step 1: Understanding the Skill with Concrete Examples

Clearly understand concrete examples of how the skill will be used. Ask users:

- "What functionality should this skill support?"
- "Can you give examples of how it would be used?"
- "What would trigger this skill?"

Skip only when usage patterns are already clearly understood.

## Step 2: Planning Reusable Contents

Analyze each example to identify what resources would be helpful:

**Example 1 - PDF Editor**:

- Rotating PDFs requires rewriting code each time
- -> Create `scripts/rotate_pdf.py`

**Example 2 - Frontend Builder**:

- Webapps need same HTML/React boilerplate
- -> Create `assets/hello-world/` template

**Example 3 - BigQuery**:

- Queries require rediscovering table schemas
- -> Create `references/schema.md`

## Step 3: Initialize the Skill

Run the init script from plugin-dev:

```bash
uv run plugins/plugin-dev/scripts/skill-creator/init_skill.py <skill-name> --path <target-path>
```

Creates: skill directory + SKILL.md template + example resource directories

## Step 4: Edit the Skill

**Writing Style**: Imperative/infinitive form (verb-first), not second person

- "To accomplish X, do Y"
- "You should do X"

**SKILL.md must include**:

1. What is the purpose? (few sentences)
2. When should it be used? (trigger keywords in description)
3. How should Claude use bundled resources?
4. **Task Templates** - Pre-defined tasks for common scenarios
5. **Post-Change Checklist** - Self-maintenance verification

**Start with resources** (`scripts/`, `references/`, `assets/`), then update SKILL.md

## Step 5: Validate the Skill

**For local development** (validation only, no zip creation):

```bash
uv run plugins/plugin-dev/scripts/skill-creator/quick_validate.py <path/to/skill-folder>
```

**For distribution** (validates AND creates zip):

```bash
uv run plugins/plugin-dev/scripts/skill-creator/package_skill.py <path/to/skill-folder>
```

Validates: YAML frontmatter, naming, description, file organization

**Note**: Use `quick_validate.py` for most workflows. Only use `package_skill.py` when actually distributing the skill to others.

## Step 6: Register and Iterate

1. Register skill in project CLAUDE.md (Workspace Skills section)
2. Use skill on real tasks
3. Notice struggles/inefficiencies
4. Update SKILL.md or resources
5. Test again
6. Verify against [Skill Quality Checklist](./task-templates.md#skill-quality-checklist)
