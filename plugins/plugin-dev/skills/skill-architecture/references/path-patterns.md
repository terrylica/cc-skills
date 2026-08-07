<!-- SKILL-PLUGIN-ROOT-OK: the canonical teaching doc for this variable's rules -->

# Path Patterns Reference

Safe and unsafe patterns for referencing bundled scripts and files in Claude Code skills and plugins.

---

## Known Limitations

> **Known Limitation**: `${CLAUDE_PLUGIN_ROOT}` is NOT a shell environment variable and should not be used
> in `SKILL.md` bodies. Use `cc-plugin-root <plugin>` instead to resolve the live plugin install path.
>
> **Reference**: [Binary Analysis (2026-08-05)](./advanced-topics.md#known-limitations) and the
> [`cc-plugin-root` resolver](https://github.com/terrylica/cc-skills/blob/main/scripts/cc-plugin-root)

---

## Safe Patterns (Use These)

### Pattern 1: Use `cc-plugin-root` in Skills (Recommended for SKILL.md)

For skills, resolve the live plugin install path using the `cc-plugin-root` helper:

```bash
/usr/bin/env bash << 'SAFE_PATTERN_1_EOF'
SCRIPT="$(cc-plugin-root plugin-name)/skills/my-skill/run.sh"
bash "$SCRIPT"
SAFE_PATTERN_1_EOF
```

**Example** (doc-tools plugin):

```bash
/usr/bin/env bash << 'DOC_TOOLS_EXAMPLE_EOF'
SCRIPT="$(cc-plugin-root doc-tools)/skills/terminal-print/assets/print-terminal.sh"
bash "$SCRIPT"
DOC_TOOLS_EXAMPLE_EOF
```

**Why it works**: `cc-plugin-root` reads `~/.claude/plugins/installed_plugins.json` (the authoritative registry) and returns the current installed path. This is the ONLY reliable way to locate a plugin from a skill.

**Do not glob** `~/.claude/plugins/cache/<publisher>/<plugin>/*` for the highest semver — that directory retains every past version and globbing often picks a stale, orphaned version.

### Pattern 2: Explicit Marketplace Fallback (For Inline Scripts)

If you must use a fallback pattern (e.g., for pre-installation bootstrap), use an explicit marketplace path:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
```

**Why it works**: In a `hooks.json` file, `${CLAUDE_PLUGIN_ROOT}` IS substituted. If the substitution fails, the fallback is used. **Never use this in a SKILL.md body** — `CLAUDE_PLUGIN_ROOT` is not a shell variable there.

### Pattern 3: Relative Links in Markdown

For documentation links within the same skill/plugin:

```markdown
See [Security Practices](./references/security-practices.md) for details.
```

**Why it works**: Relative paths resolve correctly regardless of installation location.

### Pattern 3: Direct Script Execution (in .sh files)

Inside bash scripts (not markdown), self-relative paths work:

```bash
/usr/bin/env bash << 'PATH_PATTERNS_SCRIPT_EOF_2'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# Now use $PLUGIN_DIR for other resources
PATH_PATTERNS_SCRIPT_EOF_2
```

**Why it works**: `${BASH_SOURCE[0]}` is set correctly when the script runs.

---

## Unsafe Patterns (Do NOT Use in Markdown)

### Pattern 1: Bare `${CLAUDE_PLUGIN_ROOT}` in SKILL.md

```bash
# ❌ DOES NOT WORK in SKILL.md bodies
# LAYER3-STRIPPED-PATH-OK: demonstrating unsafe pattern for documentation
bash "${CLAUDE_PLUGIN_ROOT}/skills/my-skill/run.sh"
```

**Why it fails**: `CLAUDE_PLUGIN_ROOT` is not a shell environment variable. It is substituted ONLY in manifest files (`hooks.json`, `.mcp.json`), never in `SKILL.md` bodies. The expansion produces empty string, resulting in `/skills/my-skill/run.sh` (exit 127).

**Fix**: Use `cc-plugin-root plugin-name` instead (see Safe Pattern 1).

### Pattern 2: `${CLAUDE_PLUGIN_ROOT:-fallback}` in SKILL.md

```bash
# ❌ DOES NOT WORK in SKILL.md bodies - only takes fallback
# LAYER3-STRIPPED-PATH-OK: demonstrating unsafe pattern for documentation
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/foo}/skills"
```

**Why it fails**: The braces-close-immediately rule means `${CLAUDE_PLUGIN_ROOT:-fallback}` is never substituted (the regex requires `}` right after the name). So this idiom "works" ONLY by always using the fallback, silently pinning your skill to a stale marketplace mirror instead of the installed version.

**Fix**: Use `cc-plugin-root plugin-name` instead (see Safe Pattern 1).

### Pattern 3: `$(dirname "$0")` in Markdown

```bash
# ❌ DOES NOT WORK in command/skill markdown files
# LAYER3-STRIPPED-PATH-OK: demonstrating unsafe pattern for documentation
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}/skills"
```

**Why it fails**: `$0` is not set to the markdown file path when Claude reads the file. The expansion produces garbage or empty string. Also, `${CLAUDE_PLUGIN_ROOT:-...}` never substitutes with a fallback (see Unsafe Pattern 2).

### Pattern 4: Assuming Fixed Installation Path

```bash
# ❌ FRAGILE - assumes specific installation location
# LAYER3-STRIPPED-PATH-OK: demonstrating unsafe pattern for documentation
bash ~/.claude/plugins/itp/scripts/my-script.sh
```

**Why it fails**: Marketplace plugins install to `~/.claude/plugins/marketplaces/<publisher>/<plugin>/`, not `~/.claude/plugins/<plugin>/`.

### Pattern 5: Hardcoded User-Specific Paths

```bash
# ❌ BREAKS on other machines
find /Users/terryli/.claude/skills -name "SKILL.md"
cd /home/alice/projects
```

**Why it fails**: User-specific paths only work on the developer's machine. Always use `$HOME`:

```bash
# ✅ WORKS for all users
find "$HOME/.claude/skills" -name "SKILL.md"
```

### Pattern 6: Hardcoded Temp Directories

```python
# ❌ Not portable (Windows, permissions, cleanup)
output_dir = "/tmp/jscpd-report"
```

**Why it fails**: `/tmp` doesn't exist on Windows, may have permissions issues, and doesn't clean up.

```python
# ✅ WORKS - proper temp directory handling
import tempfile
with tempfile.TemporaryDirectory() as tmpdir:
    output_dir = Path(tmpdir)
    # Auto-cleans when context exits
```

### Pattern 7: Hardcoded Binary Locations

```bash
# ❌ Assumes specific installation location
/opt/homebrew/bin/graph-easy --as=boxart
~/.local/bin/uv publish
```

**Why it fails**: Tools can be installed via different methods (mise, homebrew, apt, cargo, etc.).

```bash
# ✅ WORKS - uses PATH resolution
graph-easy --as=boxart

# ✅ WORKS - command exists check first
command -v uv &>/dev/null || { echo "uv not found"; exit 1; }
uv publish
```

---

## Context-Specific Guidance

| Context              | Safe Pattern                       | Notes                                          |
| -------------------- | ---------------------------------- | ---------------------------------------------- |
| **SKILL.md**         | `cc-plugin-root` (Pattern 1)       | Use for bash commands; relative links for docs |
| **commands/\*.md**   | `cc-plugin-root` or relative links | Never use `${CLAUDE_PLUGIN_ROOT}` or `$0`      |
| **scripts/\*.sh**    | `${BASH_SOURCE[0]}`                | Self-relative paths work in actual scripts     |
| **references/\*.md** | Relative links only                | No bash execution expected                     |
| **hooks.json**       | `${CLAUDE_PLUGIN_ROOT}` (braced)   | Manifest context; substitution works here      |

---

## Validation Checklist

When reviewing skills/plugins for path issues:

**Markdown Files (.md):**

- [ ] No `$(dirname "$0")` in any `.md` file
- [ ] No `$(dirname "$SCRIPT_DIR")` in any `.md` file
- [ ] No bare `${CLAUDE_PLUGIN_ROOT}` without a fallback (only use in `hooks.json`, not in SKILL.md)
- [ ] SKILL.md files use `cc-plugin-root <plugin>` for plugin path resolution
- [ ] No `${CLAUDE_PLUGIN_ROOT:-fallback}` in SKILL.md (the fallback never activates)
- [ ] Relative links used for internal documentation

**Scripts (.sh, .py):**

- [ ] No hardcoded `/Users/<username>` or `/home/<username>` paths
- [ ] Use `$HOME` or environment variables instead of user-specific paths
- [ ] Use `tempfile` module (Python) or `mktemp` (Bash) for temp directories
- [ ] Use `command -v` or PATH resolution for tool execution
- [ ] No hardcoded binary locations like `~/.local/bin/tool` or `/opt/homebrew/bin/tool`

---

## Environment Variable Expansion by Context

**Critical**: Environment variables like `$HOME` and `${VAR}` are NOT universally expanded. Expansion depends on the execution context.

| Context                       | `$HOME` Expanded? | `${VAR}` Expanded? | Notes                                                |
| ----------------------------- | ----------------- | ------------------ | ---------------------------------------------------- |
| **JSON config files**         | **NO**            | **NO**             | JSON is literal text - never expands                 |
| **Bash scripts**              | YES               | YES                | Shell expands variables                              |
| **Heredoc in markdown**       | YES               | YES                | Executed by shell via `/usr/bin/env bash`            |
| **Python with `shell=True`**  | YES               | YES                | Via shell subprocess                                 |
| **Python with `shell=False`** | **NO**            | **NO**             | Use `os.path.expanduser()` or `os.path.expandvars()` |
| **YAML files**                | DEPENDS           | DEPENDS            | Tool-specific (some expand, some don't)              |
| **TOML files (mise)**         | YES               | YES                | Use `{{env.HOME}}` or `{{env.VAR}}`                  |

### JSON Config Files (CRITICAL)

**Never use `$HOME`, `~`, or `${VAR}` in JSON files.** JSON is a data format that does NOT expand environment variables.

**Wrong** (creates literal `$HOME` folder):

```json
{
  "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills"
}
```

**Correct** (absolute path):

```json
{
  "installLocation": "/Users/username/.claude/plugins/marketplaces/cc-skills"
}
```

**Affected files**:

- `~/.claude/plugins/known_marketplaces.json`
- `~/.claude/plugins/installed_plugins.json`
- `~/.claude/settings.json` (hook paths)

See [Troubleshooting: Literal $HOME Folders](/docs/troubleshooting/marketplace-installation.md#7-literal-home-folders-created-environment-variable-not-expanded) for recovery if you encounter this issue.

---

## Related Issues & Workarounds

| Issue                                                            | Description                                                             | Workaround                                                           |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------- |
| N/A                                                              | `${CLAUDE_PLUGIN_ROOT}` is not a shell environment variable in SKILL.md | Use `cc-plugin-root <plugin>` instead                                |
| [#9354](https://github.com/anthropics/claude-code/issues/9354)   | `${CLAUDE_PLUGIN_ROOT}` not expanded in command markdown                | Use `cc-plugin-root` helper or manifest context only                 |
| [#11278](https://github.com/anthropics/claude-code/issues/11278) | Plugin path resolution uses marketplace.json file path                  | `installed_plugins.json` is authoritative; `cc-plugin-root` reads it |
| [#4276](https://github.com/anthropics/claude-code/issues/4276)   | Environment variable expansion not supported in JSON                    | Use absolute paths in JSON; use shell scripts for expansion          |
| [#13138](https://github.com/anthropics/claude-code/issues/13138) | Race condition creates literal `$HOME` folders                          | Use shell wrappers to expand variables before JSON injection         |

---

## Migration Guide

If you find unsafe patterns in existing skills:

1. **Search** for bare `${CLAUDE_PLUGIN_ROOT}` in SKILL.md:

   ```bash
   grep -rn '\${CLAUDE_PLUGIN_ROOT}' --include="SKILL.md"
   ```

2. **Replace** with `cc-plugin-root`:

   ```bash
   # Before (broken in SKILL.md)
   bash "${CLAUDE_PLUGIN_ROOT}/skills/my-skill/run.sh"

   # After (works)
   SCRIPT="$(cc-plugin-root plugin-name)/skills/my-skill/run.sh"
   bash "$SCRIPT"
   ```

3. **For `hooks.json`**, keep `${CLAUDE_PLUGIN_ROOT}` (with braces). It IS substituted there.

4. **Test** by running the skill/command and verifying scripts execute correctly.
