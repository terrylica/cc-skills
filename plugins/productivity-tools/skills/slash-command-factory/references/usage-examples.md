# Usage Examples

## Generate a Preset Command

```
@slash-command-factory

Use the /research-business preset
```

**Output**: Complete business research command ready to install

---

## Generate a Custom Command

```
@slash-command-factory

Create a custom command for analyzing customer feedback and generating product insights
```

**Skill asks 5-7 questions** -> **Generates complete command** -> **Validates format** -> **Provides installation steps**

---

## Command Format (What Gets Generated)

**Example generated command** (`my-command.md`):

```markdown
---
description: Brief description of what the command does
argument-hint: [arg1] [arg2]
allowed-tools: Read, Write, Bash
model: claude-3-5-sonnet-20241022
---

# Command Instructions

Do [task] with "$ARGUMENTS":

1. **Step 1**: First action
2. **Step 2**: Second action
3. **Step 3**: Generate output

**Success Criteria**:

- Criterion 1
- Criterion 2
- Criterion 3
```

---

## Example Invocations

### Use a Preset

```
@slash-command-factory

Generate the /research-content preset command
```

-> Creates content research command with all features

---

### Create Custom Healthcare Command

```
@slash-command-factory

Create a command that generates German PTV 10 therapy applications
```

**Skill asks**:

- Purpose? (Generate PTV 10 applications)
- Tools? (Read, Write, Task)
- Agents? (Yes - health-sdk-builder related agents)
- Output? (Files - therapy application documents)
- Model? (Sonnet - for quality)

**Result**: `/generate-ptv10` command ready to use

---

### Create Business Intelligence Command

```
@slash-command-factory

Build a command for competitive SWOT analysis
```

**Skill asks 5-7 questions** -> **Generates `/swot-analysis` command** -> **Validates** -> **Ready to install**

---

## Integration with Factory Agents

**Works with**:

- factory-guide (can delegate to this skill via prompts-guide pattern)
- Existing slash commands (/build, /validate-output, etc.)

**Complements**:

- skills-guide (builds Skills)
- prompts-guide (builds Prompts)
- agents-guide (builds Agents)
- slash-command-factory (builds Commands) -- This skill

**Complete ecosystem** for building all Claude Code augmentations!
