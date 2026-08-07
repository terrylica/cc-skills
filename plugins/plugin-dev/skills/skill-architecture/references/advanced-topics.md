<!-- SKILL-PLUGIN-ROOT-OK: documents the correct and incorrect usages deliberately -->

**Skill**: [Skill Architecture](../SKILL.md)

## Part 2.5: Critical Formatting Bugs (MUST READ)

### 🚨 BUG #9817: Multiline Description Footgun

**CRITICAL**: Skills with multiline descriptions are **silently ignored** - no error message!

**What breaks** (silently ignored):

```yaml
---
name: my-skill
description: This description wraps to multiple lines
  and will be silently ignored by Claude
---
```

**What works** (single line):

```yaml
---
name: my-skill
description: This description stays on one line and works correctly.
---
```

**How to prevent**:

- ✅ Keep description under 180 characters (safe from Prettier wrapping)
- ✅ Use third person ("Reads files...") not imperative ("Read files...")
- ✅ Test with `/clear` and trigger keywords after creating skill
- ✅ If skill doesn't activate, check description length/format first

**Why it happens**: Prettier with `proseWrap: true` reformats long descriptions to wrap across lines. Claude Code's YAML parser silently fails on multiline descriptions. This is a known footgun tracked in Issue #9817.

**Validation checklist**:

- [ ] Description is single line (check with `head -5 SKILL.md`)
- [ ] Description uses third person ("Does X", not "Do X")
- [ ] Description under 200 chars (CLI max is 1024 but Prettier wraps ~80)
- [ ] Test activation with `/clear` and trigger keywords

## Part 4: Content Sections (Recommended)

After YAML frontmatter, organize content:

````markdown
# Agent Skill Name

Brief introduction (1-2 sentences).

## Instructions

Step-by-step guidance in **imperative mood**:

1. Read the file using Read tool
2. Process content with scripts/helper.py
3. Verify output

## Examples

Concrete usage:

```
Input: process_data.csv
Action: Run scripts/validate.py && scripts/process.py
Output: cleaned_data.csv with 1000 rows
```

## References

For detailed API specs, see reference.md.
For advanced examples, see examples.md.
````

**Writing style**:

- ✅ **Imperative**: "Read the file", "Run the script"
- ❌ **Suggestive**: "You should read", "Maybe try"

---

## Part 5: Agent Skill Composition & Limitations

### What Agent Skills CAN'T Do

❌ **Explicitly reference other Agent Skills**:

```markdown
# ❌ WRONG - Agent Skills can't call each other directly

"First use the api-auth skill, then use api-client skill"
```

### What Agent Skills CAN Do

✅ **Claude uses multiple Agent Skills automatically**:

- If both `api-auth` and `api-client` are relevant, Claude loads both
- No explicit coordination needed
- Agent Skills work together organically based on descriptions

---

## Part 6: Claude Code vs API Differences

| Feature           | Claude Code                           | Claude.ai API           |
| ----------------- | ------------------------------------- | ----------------------- |
| File name         | `SKILL.md` (uppercase)                | `SKILL.md` (uppercase)  |
| Location          | `~/.claude/skills/`                   | ZIP upload              |
| Description limit | 1024 characters                       | Max 1024 chars          |
| `allowed-tools`   | ✅ Supported                          | ❌ Not supported        |
| Privacy           | Personal or project                   | Individual account only |
| Package install   | `claude plugin install` / marketplace | Pre-installed only      |

### Plugin-Level Features

Plugins (which contain skills) support additional configuration beyond individual skill frontmatter:

| Feature        | Purpose                                      | Defined In    |
| -------------- | -------------------------------------------- | ------------- |
| `outputStyles` | Custom formatting rules for skill output     | `plugin.json` |
| `lspServers`   | Language server integrations                 | `plugin.json` |
| `mcpServers`   | Model Context Protocol server connections    | `plugin.json` |
| `settings`     | Default settings applied when plugin enabled | `plugin.json` |

**This Agent Skill teaches CLI format only.**

---

## Known Issue Table Pattern

For skills that handle troubleshooting, use a structured table mapping symptoms to fixes. Place the table in the SKILL.md body for immediate access during diagnostics.

### Table Structure

| Column       | Content              | Example                                   |
| ------------ | -------------------- | ----------------------------------------- |
| Issue        | User-visible symptom | "No output produced"                      |
| Likely Cause | Technical root cause | "Stale lock file prevents execution"      |
| Diagnostic   | Command to confirm   | `stat /path/to/lock && cat /path/to/lock` |
| Fix          | Command to resolve   | `rm -f /path/to/lock`                     |

### Example

```markdown
| Issue                  | Likely Cause        | Diagnostic             | Fix                        |
| ---------------------- | ------------------- | ---------------------- | -------------------------- |
| No output              | Stale lock file     | `stat /tmp/app.lock`   | `rm -f /tmp/app.lock`      |
| Service not responding | Process crashed     | `pgrep -la service`    | Restart service            |
| Slow performance       | CPU fallback active | Check GPU availability | Reinstall with GPU support |
| Double execution       | Race condition      | Check lock age + PID   | Kill duplicate, clean lock |
```

### Design Guidelines

1. **Keep in SKILL.md body**: The table should load immediately when the diagnostic skill triggers (Level 2 content)
2. **Detail in references**: Create `references/common-issues.md` with expanded diagnostic procedures per issue
3. **Resolution trees**: For complex issues with multiple possible causes, use branching logic in references
4. **Cross-reference skills**: When the fix requires another skill (e.g., "run the health check skill"), name it explicitly
5. **Maintain actively**: Update the table when new issues are discovered during real usage

### Integration with Symptom Collection

Combine with [Interactive Patterns](./interactive-patterns.md) Pattern 4 (Symptom Collection):

1. Collect symptoms via AskUserQuestion
2. Match symptoms against Known Issue Table
3. Run the Diagnostic command to confirm
4. Apply the Fix
5. Verify resolution

---

## Hook Integration Pattern

Plugins can include hooks for event-driven automation that runs outside of conversation context. Hooks execute on Claude Code lifecycle events (session start, tool use, session stop).

### Structure

```
my-plugin/
├── hooks/
│   ├── hooks.json              # Hook registration (declarative)
│   └── my-event-handler.ts     # Hook implementation
```

### hooks.json Format

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/my-plugin/hooks/my-handler.ts",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

**Available events**: `PreToolUse`, `PostToolUse`, `Stop` (see Hooks Development Guide in repo docs)

> **`${CLAUDE_PLUGIN_ROOT}` — where it works, and where it silently doesn't** (corrected 2026-08-05)
>
> An earlier revision of this table had it backwards. Verified by disassembling the shipping
> Claude Code binary (2026-08-05): the substitution helper is
> `e.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, pluginPath)` and hook subprocesses are spawned with
> `env.CLAUDE_PLUGIN_ROOT` set. Two consequences that trip people up:
>
> 1. **Braces are mandatory.** Only the exact literal `${CLAUDE_PLUGIN_ROOT}` is substituted.
>    The bare `$CLAUDE_PLUGIN_ROOT` is never substituted anywhere — and neither is
>    `${CLAUDE_PLUGIN_ROOT:-fallback}`, because the regex requires the closing brace right
>    after the name. (That idiom still "works", but only by always taking the fallback.)
> 2. **It is not a Bash-tool variable.** It is never exported into the shell the model runs
>    commands in, so a SKILL.md body that writes `"$CLAUDE_PLUGIN_ROOT/skills/x/run.sh"`
>    expands it to empty and calls `/skills/x/run.sh` → exit 127.
>
> | Context                                            | `${CLAUDE_PLUGIN_ROOT}` works? | Why                                                          |
> | -------------------------------------------------- | ------------------------------ | ------------------------------------------------------------ |
> | A plugin's own `hooks/hooks.json`                  | **YES**                        | Substituted at load; also injected into the hook's env       |
> | `.mcp.json` / `.lsp.json` / monitor commands       | **YES**                        | Same substitution pass; also set in the subprocess env       |
> | Hook command copied into `~/.claude/settings.json` | **NO**                         | Not plugin-associated — nothing substitutes, no env var      |
> | A `SKILL.md` body (Bash the model runs)            | **NO**                         | Served verbatim on the Skill-tool path; not in the shell env |
> | `$HOME`                                            | YES                            | A real shell variable in every context                       |
> | `$CLAUDE_PROJECT_DIR`                              | in hooks only                  | Substituted + set for hooks; also arrives in hook stdin JSON |
>
> **In `hooks.json`, prefer `${CLAUDE_PLUGIN_ROOT}`** — it is the documented, version-correct
> form. Use `$HOME`-based absolute paths only for hooks you hand-write into `settings.json`.
>
> **In a `SKILL.md`, never reference it at all.** Resolve the plugin's live install path with
> the `cc-plugin-root` helper (`scripts/cc-plugin-root`), which reads
> `~/.claude/plugins/installed_plugins.json`:
>
> ```bash
> SCRIPT="$(cc-plugin-root my-plugin)/skills/my-skill/run.sh"
> ```
>
> Do **not** glob `~/.claude/plugins/cache/<mp>/<plugin>/*` and take the highest version —
> that directory retains every past version and the highest one is often orphaned.

### When to Use Hooks

- **Cross-session automation**: Notifications when a session ends
- **Event-driven actions**: Validate tool output, enforce policies
- **Integration with external systems**: Send alerts to messaging platforms
- **Telemetry**: Log session activity for audit or analysis

### Design Guidelines

1. **Hooks run outside conversation** - No user interaction (no AskUserQuestion)
2. **Respect timeout** - Keep execution fast (typically 10s max)
3. **Fail silently** - Hooks should not block Claude Code operation on failure
4. **File-based communication** - Write to notification directories rather than calling APIs directly from hooks
5. **Provide a management command** - Include a `/plugin:hooks` command for install/uninstall/status (see [Command-Skill Duality](./invocation-control.md))
6. **Use `${CLAUDE_PLUGIN_ROOT}` in `hooks.json`** - braces required; fall back to `$HOME`-based absolute paths only for hooks hand-written into `settings.json`. Never reference it from a `SKILL.md` body — use `cc-plugin-root <plugin>` there (see the table above)
