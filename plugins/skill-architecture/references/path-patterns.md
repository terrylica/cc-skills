# Path Patterns Reference

Safe and unsafe patterns for referencing bundled scripts and files in Claude Code skills and plugins.

---

## Known Limitations

> **Bug**: `${CLAUDE_PLUGIN_ROOT}` environment variable does NOT expand in command markdown files.
>
> **Issue**: [#9354 - Fix ${CLAUDE_PLUGIN_ROOT} in command markdown](https://github.com/anthropics/claude-code/issues/9354)
>
> **Status**: Open (as of 2024-12)

---

## Safe Patterns (Use These)

### Pattern 1: Explicit Fallback Path (Recommended)

For marketplace plugins, use explicit fallback to the marketplace installation path:

```bash
# Environment-agnostic with explicit marketplace fallback
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/<publisher>/<plugin-name>}"
bash "$PLUGIN_DIR/scripts/my-script.sh"
```

**Example** (itp plugin):

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh" --check
```

**Why it works**: When `${CLAUDE_PLUGIN_ROOT}` isn't set (which is the case in markdown files due to bug #9354), the explicit fallback path is used.

### Pattern 2: Relative Links in Markdown

For documentation links within the same skill/plugin:

```markdown
See [Security Practices](./references/security-practices.md) for details.
```

**Why it works**: Relative paths resolve correctly regardless of installation location.

### Pattern 3: Direct Script Execution (in .sh files)

Inside bash scripts (not markdown), self-relative paths work:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
# Now use $PLUGIN_DIR for other resources
```

**Why it works**: `${BASH_SOURCE[0]}` is set correctly when the script runs.

---

## Unsafe Patterns (Do NOT Use in Markdown)

### Pattern 1: `$(dirname "$0")` in Markdown

```bash
# ❌ DOES NOT WORK in command/skill markdown files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
```

**Why it fails**: `$0` is not set to the markdown file path when Claude reads the file. The expansion produces garbage or empty string.

### Pattern 2: Bare `${CLAUDE_PLUGIN_ROOT}` Without Fallback

```bash
# ❌ DOES NOT WORK - no fallback when variable unset
bash "${CLAUDE_PLUGIN_ROOT}/scripts/my-script.sh"
```

**Why it fails**: Due to bug #9354, `${CLAUDE_PLUGIN_ROOT}` is not expanded in markdown files, resulting in `/scripts/my-script.sh` (missing the plugin path).

### Pattern 3: Assuming Fixed Installation Path

```bash
# ❌ FRAGILE - assumes specific installation location
bash ~/.claude/plugins/itp/scripts/my-script.sh
```

**Why it fails**: Marketplace plugins install to `~/.claude/plugins/marketplaces/<publisher>/<plugin>/`, not `~/.claude/plugins/<plugin>/`.

### Pattern 4: Hardcoded User-Specific Paths

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

### Pattern 5: Hardcoded Temp Directories

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

### Pattern 6: Hardcoded Binary Locations

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

| Context              | Safe Pattern                        | Notes                                      |
| -------------------- | ----------------------------------- | ------------------------------------------ |
| **SKILL.md**         | Explicit fallback or relative links | Use Pattern 1 for bash, Pattern 2 for docs |
| **commands/\*.md**   | Explicit fallback only              | `$0` doesn't work here                     |
| **scripts/\*.sh**    | `${BASH_SOURCE[0]}`                 | Self-relative paths work in actual scripts |
| **references/\*.md** | Relative links only                 | No bash execution expected                 |

---

## Validation Checklist

When reviewing skills/plugins for path issues:

**Markdown Files (.md):**

- [ ] No `$(dirname "$0")` in any `.md` file
- [ ] No `$(dirname "$SCRIPT_DIR")` in any `.md` file
- [ ] All `${CLAUDE_PLUGIN_ROOT}` usages have explicit fallback
- [ ] Fallback paths match actual marketplace structure
- [ ] Relative links used for internal documentation

**Scripts (.sh, .py):**

- [ ] No hardcoded `/Users/<username>` or `/home/<username>` paths
- [ ] Use `$HOME` or environment variables instead of user-specific paths
- [ ] Use `tempfile` module (Python) or `mktemp` (Bash) for temp directories
- [ ] Use `command -v` or PATH resolution for tool execution
- [ ] No hardcoded binary locations like `~/.local/bin/tool` or `/opt/homebrew/bin/tool`

---

## Related Issues

| Issue                                                            | Description                                              | Status |
| ---------------------------------------------------------------- | -------------------------------------------------------- | ------ |
| [#9354](https://github.com/anthropics/claude-code/issues/9354)   | `${CLAUDE_PLUGIN_ROOT}` not expanded in command markdown | Open   |
| [#11278](https://github.com/anthropics/claude-code/issues/11278) | Plugin path resolution uses marketplace.json file path   | Open   |

---

## Migration Guide

If you find unsafe patterns in existing skills:

1. **Search** for the pattern:

   ```bash
   grep -rn 'dirname.*\$0\|dirname.*\$SCRIPT_DIR' --include="*.md"
   ```

2. **Replace** with explicit fallback:

   ```bash
   # Before (broken)
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

   # After (works)
   PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/<publisher>/<plugin>}"
   ```

3. **Test** by running the command/skill and verifying scripts execute correctly.
