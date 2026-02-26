**Skill**: [Skill Architecture](../SKILL.md)

# Troubleshooting

## Quick Reference

| Issue                  | Cause                          | Solution                                                                                                                |
| ---------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Skill not triggering   | Missing trigger keywords       | Add trigger phrases to description field                                                                                |
| YAML parse error       | Colon in description           | Replace colons with dashes in description                                                                               |
| Skill not found        | Wrong location or not synced   | Standalone: place in `~/.claude/skills/` or project `.claude/skills/`. Marketplace: run `mise run release:full` to sync |
| validate script fails  | Invalid frontmatter            | Check name format (lowercase-hyphen only)                                                                               |
| Resources not loading  | Wrong path in SKILL.md         | Use relative paths from skill directory                                                                                 |
| Script execution fails | Missing shebang or permissions | Add `#!/usr/bin/env python3` and `chmod +x`                                                                             |
| allowed-tools ignored  | API skill (not CLI)            | allowed-tools only works in CLI skills                                                                                  |
| Description too long   | Over 1024 chars                | Shorten description, move details to SKILL.md body                                                                      |

## Detailed Troubleshooting

### "Skill not activating"

**Cause**: Description doesn't match user query

**Fix**: Add more trigger keywords

```yaml
# Before
description: PDF manipulation tool

# After
description: Extract text and tables from PDFs, rotate pages, merge documents. Use when working with PDF files or when user mentions forms, contracts, document processing.
```

### "SKILL.md too long"

**Cause**: Too much detail in main file

**Fix**: Use progressive disclosure - move details to `references/`, keep only essential info in SKILL.md, add navigation links.

### "Skill loaded but fails"

**Cause**: Instructions unclear or incomplete

**Fix**: Add specific examples, include error handling, test instructions manually first.

### "Validation fails"

**Cause**: Structural or format issues

**Fix**: Run validation script for details:

```bash
uv run plugins/plugin-dev/scripts/skill-creator/quick_validate.py <skill-path>
```
