# Link Patterns Reference

Comprehensive guide to markdown link patterns and portability validation.

**Parent**: [Link Validator Skill](../SKILL.md)

---

## Violation Patterns

The validator detects absolute repository paths that break when skills are installed elsewhere.

### Detection Regex

```regex
^/(?!/)(?!https?:)(?!#)
```

**Breakdown:**

- `^/` - Starts with forward slash
- `(?!//)` - NOT followed by another slash (excludes `//cdn...`)
- `(?!https?:)` - NOT followed by `http:` or `https:`
- `(?!#)` - NOT followed by `#` (excludes anchors)

### Examples of Violations

| Link                               | Why It's a Violation                                       |
| ---------------------------------- | ---------------------------------------------------------- |
| `[Guide](/skills/foo/guide.md)`    | Absolute repo path - won't exist in installed location     |
| `[ADR](/docs/adr/2025-01-01.md)`   | Absolute repo path - repo structure not preserved          |
| `[Script](/plugins/bar/script.sh)` | Absolute repo path - plugin installs to different location |

---

## Valid Patterns

### Relative Same Directory (`./`)

```markdown
[Reference Guide](./references/guide.md)
[Helper Script](./scripts/helper.py)
```

**Use when:** Linking to files within the same skill directory.

### Relative Parent (`../`)

```markdown
[Sibling Skill](../other-skill/SKILL.md)
[Plugin README](../../README.md)
```

**Use when:** Linking to sibling skills or parent directories.

### Implicit Relative (No Prefix)

```markdown
[Same Dir File](guide.md)
```

**Use when:** Linking to files in the exact same directory. Less explicit than `./`.

### External URLs

```markdown
[GitHub](https://github.com/user/repo)
[Documentation](https://docs.example.com)
```

**Always valid:** External URLs are not subject to portability checks.

### Anchor Links

```markdown
[Section](#installation)
[Quick Start](#quick-start)
```

**Always valid:** In-page anchors work regardless of file location.

---

## Common Scenarios

### Scenario 1: SKILL.md to Own References

**Location:** `skill-name/SKILL.md`
**Target:** `skill-name/references/guide.md`

```markdown
# Correct

[Guide](./references/guide.md)

# Wrong

[Guide](/skills/skill-name/references/guide.md)
```

### Scenario 2: References Back to SKILL.md

**Location:** `skill-name/references/guide.md`
**Target:** `skill-name/SKILL.md`

```markdown
# Correct

[Back to Skill](../SKILL.md)

# Wrong

[Back to Skill](/skills/skill-name/SKILL.md)
```

### Scenario 3: Cross-Skill Reference

**Location:** `skill-a/SKILL.md`
**Target:** `skill-b/SKILL.md`

```markdown
# Correct

[Related Skill](../skill-b/SKILL.md)

# Wrong

[Related Skill](/skills/skill-b/SKILL.md)
```

### Scenario 4: Deep Reference to Other Skill

**Location:** `skill-a/references/deep/file.md`
**Target:** `skill-b/SKILL.md`

```markdown
# Correct (3 levels up, then into skill-b)

[Other Skill](../../../skill-b/SKILL.md)

# Wrong

[Other Skill](/skills/skill-b/SKILL.md)
```

---

## Fix Calculation Logic

The validator suggests fixes based on file depth:

### Depth Calculation

```
skill-root/SKILL.md           → depth 0
skill-root/references/foo.md  → depth 1
skill-root/references/a/b.md  → depth 2
```

### Fix Formula

**Same skill, different directory:**

```
../  × depth  +  target-path
```

**Different skill:**

```
../  × (depth + 1)  +  skill-name/target-path
```

---

## Testing Fixes

### Local Verification

1. Apply the suggested fix
2. Run validator again: `uv run scripts/validate_links.py <skill-path>`
3. Verify exit code 0

### Installation Test

1. Copy skill to different location:
   ```bash
   cp -r ~/.claude/skills/my-skill /tmp/test-skill
   ```
2. Run validator on new location
3. Manually verify links resolve in new context

---

## Edge Cases

### Code Blocks (Skipped)

Links inside fenced code blocks are NOT validated:

    ```markdown
    This [link](/absolute/path.md) is in a code block - ignored
    ```

(The above indented block shows a code fence that would be skipped)

### Inline Code (Skipped)

Links in inline code are NOT validated:

```markdown
Use the pattern `[text](/path)` for documentation - ignored
```

### Empty Links (Allowed)

```markdown
[Empty link]() # Passes - no path to validate
```

---

## Integration Notes

### With skill-architecture

The skill-architecture plugin references link-validator for:

- TodoWrite template step 9 (Create New Skill)
- Skill Quality Checklist item

### With CI/CD

Exit codes enable CI integration:

```yaml
- name: Validate Links
  run: |
    uv run plugins/link-validator/scripts/validate_links.py ./skills/
    # Fails build if violations found (exit 1)
```
