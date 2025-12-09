---
adr: 2025-12-08-clickhouse-cloud-management-skill
source: ~/.claude/plans/spicy-conjuring-planet.md
implementation-status: released
phase: phase-3
last-updated: 2025-12-08
release: v2.20.0
---

# Design Spec: Extract ClickHouse Cloud Management Skill

**ADR**: [Extract ClickHouse Cloud Management Skill](/docs/adr/2025-12-08-clickhouse-cloud-management-skill.md)

## Summary

Extract ClickHouse Cloud management content from `~/.claude/CLAUDE.md` to a new skill `clickhouse-cloud-management` in the `devops-tools` plugin. Follow Anthropic's official skill creation process and validate using `plugin-dev` agents.

**Validation Arsenal** (from Anthropic `plugin-dev` plugin):

- `plugin-dev:skill-development` skill - Creation guidance (loaded)
- `plugin-dev:skill-reviewer` agent - Post-creation quality review
- `plugin-dev:plugin-validator` agent - Plugin structure validation

---

## Implementation Steps

### Step 1: Create Skill Directory Structure

```bash
mkdir -p ~/eon/cc-skills/plugins/devops-tools/skills/clickhouse-cloud-management/{references,scripts}
touch ~/eon/cc-skills/plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md
```

**Target files**:

| File                         | Purpose                                       |
| ---------------------------- | --------------------------------------------- |
| `SKILL.md`                   | Lean core content (target: 1,500-2,000 words) |
| `references/sql-patterns.md` | Detailed SQL examples and patterns            |
| `scripts/test-connection.sh` | Connection testing utility (optional)         |

### Step 2: Create SKILL.md with Proper Frontmatter

**Frontmatter** (third-person with specific trigger phrases):

```yaml
---
name: clickhouse-cloud-management
description: This skill should be used when the user asks to "create ClickHouse user", "manage ClickHouse permissions", "test ClickHouse connection", "troubleshoot ClickHouse Cloud", or mentions ClickHouse Cloud credentials, API keys, or SQL user management.
allowed-tools: Read, Bash
---
```

**Body content** (imperative form, NOT second person):

- Overview of ClickHouse Cloud management options
- Capability Matrix (SQL vs Console) - what's possible where
- Quick reference for common operations
- Password requirements (ClickHouse Cloud enforced)
- Pointer to `references/sql-patterns.md` for detailed examples

**Writing style requirements**:

- Use imperative: "Create user with...", NOT "You should create..."
- Keep lean: ~1,500-2,000 words in SKILL.md body
- Move detailed SQL to `references/sql-patterns.md`

### Step 3: Create references/sql-patterns.md

**Content to move from CLAUDE.md**:

- Full SQL syntax examples (CREATE USER, GRANT, DROP USER)
- curl command patterns for HTTP interface
- Connection string formats
- Advanced permission patterns

### Step 4: Update ~/.claude/CLAUDE.md

**Remove** (lines ~332-369):

- ClickHouse User Management via SQL section
- Capability Matrix table
- SQL syntax examples
- Password requirements paragraph

**Keep in CLAUDE.md** (credentials stay in hub):

- 1Password items table (ClickHouse Cloud API Keys + gapless-deribit-clickhouse)

**Add skill reference**:

```markdown
### ClickHouse Cloud Management

For ClickHouse Cloud user management, SQL operations, and credential setup, see the `devops-tools:clickhouse-cloud-management` skill.
```

### Step 5: Validate with plugin-dev Agents

**5a. Run skill-reviewer agent**:

```
Invoke Task tool with subagent_type='plugin-dev:skill-reviewer'
Prompt: "Review the clickhouse-cloud-management skill at ~/eon/cc-skills/plugins/devops-tools/skills/clickhouse-cloud-management/"
```

**Validation checklist** (from skill-development guide):

- [ ] Frontmatter has `name` and `description` fields
- [ ] Description uses third person ("This skill should be used when...")
- [ ] Description includes specific trigger phrases
- [ ] Body uses imperative/infinitive form (NOT second person)
- [ ] SKILL.md is lean (1,500-2,000 words)
- [ ] Detailed content moved to references/
- [ ] All referenced files exist

**5b. Run plugin-validator agent**:

```
Invoke Task tool with subagent_type='plugin-dev:plugin-validator'
Prompt: "Validate the devops-tools plugin at ~/eon/cc-skills/plugins/devops-tools/"
```

---

## Critical Files

| Priority | File                                                                                                 | Change                                          |
| -------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 1        | `~/eon/cc-skills/plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md`                   | Create new skill                                |
| 2        | `~/eon/cc-skills/plugins/devops-tools/skills/clickhouse-cloud-management/references/sql-patterns.md` | Detailed SQL examples                           |
| 3        | `~/.claude/CLAUDE.md`                                                                                | Replace ClickHouse section with skill reference |

---

## Skill Reference Pattern

**Key insight**: Skills installed from marketplace cannot be linked by path. Reference by name:

```markdown
# Correct - reference by skill name

See the `devops-tools:clickhouse-cloud-management` skill.

# Wrong - path won't work for marketplace plugins

See [ClickHouse Management](/skills/clickhouse-cloud-management/SKILL.md)
```

---

## Verification Workflow

1. **Create skill** following Steps 1-4
2. **Run skill-reviewer agent** - fix any issues
3. **Run plugin-validator agent** - confirm plugin structure valid
4. **Test trigger phrases** - verify skill loads on expected queries
5. **Confirm CLAUDE.md** - references skill by name, keeps 1Password table
