# Validation & Success Criteria

## Automatic Validation

Every generated command is automatically validated for:

- Valid YAML frontmatter (proper syntax, required fields)
- Correct argument format ($ARGUMENTS, not $1 $2 $3)
- **Short forms for all flags** (mandatory 1-2 letter shortcuts)
- **argument-hint includes both forms** (`[-b|--branch]`)
- **Bash subcommand-level specificity** (no `Bash(git:*)`, use `Bash(git add:*)`)
- allowed-tools syntax (comma-separated string)
- Clean folder organization (if folders used)
- No placeholder text

**If validation fails**, you'll get specific fix instructions.

---

## Output Validation Details

**YAML Frontmatter**:

- Has `description` field
- Proper YAML syntax
- Valid frontmatter fields only

**Arguments**:

- Uses $ARGUMENTS if needed
- Has argument-hint if $ARGUMENTS used
- No $1, $2, $3 positional args
- **All flags have short forms** (1-2 letters)
- **argument-hint shows `[-short|--long]` format**

**Tools**:

- Valid tool names
- Proper comma-separated format
- Appropriate for command purpose
- **Bash uses subcommand-level** for git/gh/npm (not `Bash(git:*)`)
- **No blanket `Bash`** permission

**Organization**:

- .md files in root
- Folders properly separated
- No scattered files

---

## Success Criteria

Generated commands should:

- Have valid YAML frontmatter
- Use $ARGUMENTS (never positional)
- **All flags have short forms** (1-2 letters, e.g., `-b|--branch`)
- **argument-hint shows both forms** (`[-b|--branch]`)
- **Bash uses subcommand-level specificity** for commands with subcommands
  - `Bash(git:*)` - too broad
  - `Bash(git add:*)`, `Bash(git commit:*)` - correct
- **No blanket Bash permission** (`Bash` alone is prohibited)
- Work when copied to .claude/commands/
- Execute correctly with arguments
- Produce expected output
- Follow organizational standards

---

## Best Practices

**For Command Design**:

- Keep commands focused (one clear purpose)
- Use descriptive names (kebab-case for files)
- Document expected arguments clearly
- Include success criteria
- Add examples in TEST_EXAMPLES.md

**For Tool Selection**:

- Read: For analyzing files
- Write/Edit: For generating/modifying files
- Bash: For system commands, web research
- Task: For launching agents
- Grep/Glob: For searching code

**For Agent Integration**:

- Use Task tool to launch agents
- Specify which agents clearly
- Coordinate outputs
- Document agent roles

---

## Important Notes

**Arguments**:

- Always use `$ARGUMENTS` (all arguments as one string)
- Never use `$1`, `$2`, `$3` (positional - not used by this factory)

**Folder Organization**:

- All .md files in command root directory
- Supporting folders separate (standards/, examples/, scripts/)
- No mixing of different types

**Output Location**:

- Commands generate to: `./generated-commands/[command-name]/`
- User copies to: `.claude/commands/[command-name].md` (when ready)

---

## Troubleshooting

| Issue                     | Cause                          | Solution                                          |
| ------------------------- | ------------------------------ | ------------------------------------------------- |
| Command not found         | Not installed to commands dir  | Copy .md file to ~/.claude/commands/ or .claude/  |
| YAML syntax error         | Invalid frontmatter            | Validate YAML with `yq` or online validator       |
| $ARGUMENTS not expanding  | Using $1 $2 instead            | Use $ARGUMENTS for all arguments as single string |
| Bash permission denied    | Using blanket Bash             | Specify subcommand-level: Bash(git add:\*)        |
| Command too verbose       | Name exceeds 4 words           | Shorten to 2-4 word kebab-case name               |
| Agent not launching       | Task tool not in allowed-tools | Add Task to allowed-tools for agent commands      |
| Validation fails on flags | Missing short forms            | Add 1-2 letter shortcuts for all flags            |
| Output not generated      | Missing Write in allowed-tools | Add Write tool for file-generating commands       |
