# Generation Process

After collecting answers:

1. **Generate YAML Frontmatter**:

```yaml
---
description: [From command purpose]
argument-hint: [If $ARGUMENTS needed]
allowed-tools: [From tool selection]
model: [If specified]
---
```

1. **Generate Command Body**:

```markdown
[Purpose-specific instructions]

[If uses agents]:

1. **Launch [agent-name]** with [specific task]
2. Coordinate workflow
3. Validate results

[If uses bash]:

- Context: !`bash command`

[If uses file refs]:

- Review: @file.txt

Success Criteria: [Based on output type]
```

1. **Create Folder Structure**:

```
generated-commands/[command-name]/
├── [command-name].md    # Command file (ROOT)
├── README.md            # Installation guide (ROOT)
├── TEST_EXAMPLES.md     # Testing examples (ROOT)
└── [folders if needed]  # standards/, examples/, scripts/
```

1. **Validate Format**:

- YAML frontmatter valid
- $ARGUMENTS syntax correct (if used)
- allowed-tools format proper
- Folder organization clean

1. **Provide Installation Instructions**:

```
Your command is ready!

Output location: generated-commands/[command-name]/

To install:
1. Copy the command file:
   cp generated-commands/[command-name]/[command-name].md .claude/commands/

2. Restart Claude Code (if already running)

3. Test:
   /[command-name] [arguments]
```

## Plugin Command Invocation Format

When commands are installed in a **plugin** (via `commands/` directory), users invoke them with the full namespace:

```
/plugin-name:command-name [arguments]
```

| Installation Location              | Invocation Format           | Example                        |
| ---------------------------------- | --------------------------- | ------------------------------ |
| `~/.claude/commands/` (user-level) | `/command-name`             | `/research-business`           |
| `plugin/commands/` (plugin)        | `/plugin-name:command-name` | `/my-plugin:research-business` |

**Shortcut rules**:

- Commands like `/my-plugin:research-business` can be invoked as `/research-business` if no naming conflicts exist
- **Exception**: When `command-name` = `plugin-name` (e.g., `/foo:foo`), you **must** use the full format -- typing `/foo` alone is interpreted as the plugin prefix, not the command

## Output Structure

Commands are generated in your project's root directory:

```
[your-project]/
└── generated-commands/
    └── [command-name]/
        ├── [command-name].md      # Command file (ROOT level)
        ├── README.md              # Installation guide (ROOT level)
        ├── TEST_EXAMPLES.md       # Testing guide (ROOT level - if applicable)
        │
        ├── standards/             # Only if command has standards
        ├── examples/              # Only if command has examples
        └── scripts/               # Only if command has helper scripts
```

**Organization Rules**:

- All .md files in ROOT directory
- Supporting folders separate (standards/, examples/, scripts/)
- No mixing of different types in same folder
- Clean, hierarchical structure

## Installation

**After generation**:

1. **Review output**:

   ```bash
   ls generated-commands/[command-name]/
   ```

2. **Copy to Claude Code** (when ready):

   ```bash
   # Project-level (this project only)
   cp generated-commands/[command-name]/[command-name].md .claude/commands/

   # User-level (all projects)
   cp generated-commands/[command-name]/[command-name].md ~/.claude/commands/
   ```

3. **Restart Claude Code** (if running)

4. **Test command**:

   ```bash
   /[command-name] [arguments]
   ```
