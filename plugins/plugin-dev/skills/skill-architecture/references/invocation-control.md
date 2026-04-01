**Skill**: [Skill Architecture](../SKILL.md)

# Invocation Control

Commands and skills have been **merged** in Claude Code. Both create `/name` slash commands. Skills are recommended for all new work — they support the full feature set (description-based auto-triggering, frontmatter fields, bundled resources).

---

## Invocation Control Fields

Two frontmatter fields control how a skill is invoked:

| Field                      | Effect when `true`                               | Default |
| -------------------------- | ------------------------------------------------ | ------- |
| `disable-model-invocation` | Only manual `/name` — Claude never auto-triggers | `false` |
| `user-invocable`           | When `false`, no `/name` — Claude-only trigger   | `true`  |

### Truth Table

| `disable-model-invocation` | `user-invocable` | `/name`? | Auto-trigger? | Use case                      |
| -------------------------- | ---------------- | -------- | ------------- | ----------------------------- |
| `false` (default)          | `true` (default) | Yes      | Yes           | Most skills                   |
| `true`                     | `true`           | Yes      | No            | Hook-installation skills only |
| `false`                    | `false`          | No       | Yes           | Domain knowledge, context     |
| `true`                     | `false`          | No       | No            | Effectively disabled          |

---

## When to Use Each Mode

### Default (both omitted) — Most Skills

The skill is available via `/name` AND Claude auto-triggers it when description keywords match the conversation. This is the right choice for ~90% of skills.

### Manual-Only (`disable-model-invocation: true`)

Reserved exclusively for **hook-installation skills** (`skills/hooks/`) that modify `~/.claude/settings.json`. All other skills — including deploy, release, setup, and destructive ops — should keep the default `false` so Claude can auto-trigger them when the user's intent matches. Claude already asks for confirmation before executing side effects via `allowed-tools` restrictions.

### Background-Only (`user-invocable: false`)

Use for skills that provide context but shouldn't be manually invoked:

- **Domain knowledge**: coding standards, API schemas, business rules
- **Convention enforcement**: style guides loaded when relevant code is discussed
- **Contextual helpers**: auto-loaded when Claude detects relevant conversation topics

---

## Skill Permission Rules

When configuring `allowed-tools` in `settings.json` to permit skill invocations:

- `Skill(skill-name)` — exact match, allows one specific skill
- `Skill(skill-name *)` — prefix match, allows skill and all sub-invocations

Example in `settings.json`:

```json
{
  "permissions": {
    "allow": ["Skill(itp:go)", "Skill(devops-tools *)"]
  }
}
```

---

## Historical Note: cc-skills `commands/` Elimination

The cc-skills marketplace originally used a separate `commands/` directory alongside `skills/`. This was eliminated because:

1. **Duplication**: Each skill needed an identical copy in `commands/` to be slash-invocable
2. **Sync bugs**: `Skill()` invocations returned "Unknown skill" when only the command copy existed
3. **Maintenance burden**: Two files to update for every change

Now, `skills/<name>/SKILL.md` is the single source of truth. The `sync-commands-to-settings.sh` script reads from `skills/` directly.

See [migration issue](https://github.com/terrylica/cc-skills/issues/26) for full context.

---

## Migration Guide (Legacy `commands/`)

If a plugin still has a `commands/` directory:

1. Move command content into the corresponding `skills/<name>/SKILL.md`
2. Add `argument-hint` to frontmatter if the command accepted arguments
3. Set `disable-model-invocation: true` if the command was intentionally manual-only
4. Delete the `commands/` directory
5. Run `bun scripts/validate-plugins.mjs` to verify
