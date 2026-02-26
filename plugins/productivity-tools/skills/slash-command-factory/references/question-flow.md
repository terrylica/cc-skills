# Question Flow (Custom Path)

## Question 1: Command Purpose

"What should this slash command do?

Be specific about its purpose and when you'll use it.

Examples:

- 'Analyze customer feedback and generate actionable insights'
- 'Generate HIPAA-compliant API documentation'
- 'Research market trends and create content strategy'
- 'Extract key insights from research papers'

Your command's purpose: \_\_\_"

---

## Question 2: Arguments (Auto-Determined)

The skill automatically determines if your command needs arguments based on the purpose.

**If arguments are needed**, they will use `$ARGUMENTS` format:

- User types: `/your-command argument1 argument2`
- Command receives: `$ARGUMENTS` = "argument1 argument2"

**Examples**:

- `/research-business "Tesla" "EV market"` -> $ARGUMENTS = "Tesla EV market"
- `/medical-translate "Myokardinfarkt" "de"` -> $ARGUMENTS = "Myokardinfarkt de"

**No user input needed** - skill decides intelligently.

---

### Argument Short-Form Convention (MANDATORY)

**Every flag/option MUST have a short form** for quick command-line entry.

**Rules**:

1. **Prefer 1-letter**: `-b` for `--branch`, `-v` for `--verbose`
2. **Use 2-letters only if needed**: `-nb` for `--no-branch` (when `-n` conflicts)
3. **Document both forms**: Always show `[-short|--long]` in argument-hint

**Format in argument-hint**:

```yaml
argument-hint: "[slug] [-b|--branch] [-v|--verbose]"
```

**Format in Arguments table**:

```markdown
| Argument    | Short | Description           | Default |
| ----------- | ----- | --------------------- | ------- |
| `--branch`  | `-b`  | Create feature branch | false   |
| `--verbose` | `-v`  | Enable verbose output | false   |
```

**Letter Selection Priority**:

1. First letter of the flag name (`--branch` -> `-b`)
2. Distinctive letter if first conflicts (`--debug` -> `-d`, but if `-d` taken, use `-D` or `-db`)
3. Mnemonic association (`--quiet` -> `-q`, `--force` -> `-f`)

**This is a MANDATORY success criterion** - commands without short forms will fail validation.

---

## Question 3: Which Tools?

"Which Claude Code tools should this command use?

Available tools:

- **Read** - Read files
- **Write** - Create files
- **Edit** - Modify files
- **Bash** - Execute shell commands (MUST specify exact commands)
- **Grep** - Search code
- **Glob** - Find files by pattern
- **Task** - Launch agents

**CRITICAL**: For Bash, you MUST specify exact commands, not wildcards.

**Bash Examples**:

- Bash(git status:_), Bash(git diff:_), Bash(git log:\*)
- Bash(find:_), Bash(tree:_), Bash(ls:\*)
- Bash(grep:_), Bash(wc:_), Bash(head:\*)
- Bash (wildcard not allowed per official patterns)

**Tool Combination Examples**:

- Git command: Read, Bash(git status:_), Bash(git diff:_)
- Code generator: Read, Write, Edit
- Discovery command: Bash(find:_), Bash(tree:_), Bash(grep:\*)
- Analysis command: Read, Grep, Task (launch agents)

Your tools (comma-separated): \_\_\_"

---

## Question 4: Agent Integration

"Does this command need to launch agents for specialized tasks?

Examples of when to use agents:

- Complex analysis (launch rr-architect, rr-security)
- Implementation tasks (launch rr-frontend, rr-backend)
- Quality checks (launch rr-qa, rr-test-runner)

Options:

1. **No agents** - Command handles everything itself
2. **Launch agents** - Delegate to specialized agents

Your choice (1 or 2): \_\_\_"

If "2", ask: "Which agents should it launch? \_\_\_"

---

## Question 5: Output Type

"What type of output should this command produce?

1. **Analysis** - Research report, insights, recommendations
2. **Files** - Generated code, documentation, configs
3. **Action** - Execute tasks, run workflows, deploy
4. **Report** - Structured report with findings and next steps

Your choice (1, 2, 3, or 4): \_\_\_"

---

## Question 6: Model Preference (Optional)

"Which Claude model should this command use?

1. **Default** - Inherit from main conversation (recommended)
2. **Sonnet** - Best for complex tasks
3. **Haiku** - Fastest, cheapest (for simple commands)
4. **Opus** - Maximum capability (for critical tasks)

Your choice (1, 2, 3, or 4) or press Enter for default: \_\_\_"

---

## Question 7: Additional Features (Optional)

"Any special features?

Optional features:

- **Bash execution** - Run shell commands and include output (!`command`)
- **File references** - Include file contents (@file.txt)
- **Context gathering** - Read project files for context

Features you need (comma-separated) or press Enter to skip: \_\_\_"
