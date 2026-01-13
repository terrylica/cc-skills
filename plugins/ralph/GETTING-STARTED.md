# Getting Started with Ralph (First-Time Users)

> **Target audience**: New to Claude Code, new to plugins, new to Ralph.
> **Goal**: Get Ralph running with Alpha Forge in under 10 minutes.

## Prerequisites Checklist

Before starting, verify you have:

| Requirement         | Check Command       | Install                                                                         |
| ------------------- | ------------------- | ------------------------------------------------------------------------------- |
| Claude Code CLI     | `claude --version`  | [Install Guide](https://docs.anthropic.com/en/docs/claude-code/getting-started) |
| uv (Python manager) | `uv --version`      | `brew install uv`                                                               |
| jq (JSON processor) | `jq --version`      | `brew install jq`                                                               |
| Python 3.11+        | `python3 --version` | `mise use python@3.11`                                                          |

## Step 1: Install the cc-skills Plugin

Ralph is part of the **cc-skills** plugin collection. Install it from your **terminal** (not inside Claude Code):

```bash
# Add the cc-skills marketplace (one-time setup)
claude plugin marketplace add terrylica/cc-skills

# Install all cc-skills plugins including ralph
for p in itp plugin-dev gh-tools link-tools devops-tools dotfiles-tools doc-tools quality-tools productivity-tools mql5 itp-hooks alpha-forge-worktree ralph iterm2-layout-config statusline-tools notion-api asciinema-tools git-town-workflow; do claude plugin install "$p@cc-skills"; done

# Or install just ralph
claude plugin install ralph@cc-skills
```

**Expected output**: "Successfully installed plugin: ralph@cc-skills"

> **⚠️ "Plugin not found" or "Source path does not exist"?**
>
> **Fix** (run in your terminal):
>
> ```bash
> # Update the marketplace
> cd ~/.claude/plugins/marketplaces/cc-skills
> git pull
>
> # Retry installation
> claude plugin install ralph@cc-skills
> ```
>
> If marketplace doesn't exist, clone manually:
>
> ```bash
> git clone https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/cc-skills
> ```

**Other troubleshooting**:

- If "Marketplace not found": Run `claude plugin marketplace add terrylica/cc-skills` first
- If "Plugin not found": Check spelling — it's `ralph@cc-skills`
- For more issues: See [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md)

## Step 2: Install Ralph Hooks

Hooks are how Ralph intercepts Claude's stop signals. They must be registered in your settings:

```bash
# Still inside Claude Code
/ralph:hooks install
```

**Expected output**:

```
✓ Added 3 hooks to ~/.claude/settings.json
  - Stop hook: loop-until-done.py
  - PreToolUse: archive-plan.sh
  - PreToolUse: pretooluse-loop-guard.py

⚠️ RESTART REQUIRED: Exit Claude Code completely and relaunch.
```

## Step 3: Restart Claude Code (Critical!)

**Why restart?** Claude Code loads hooks only at startup. Installing mid-session means hooks won't activate until you restart.

**How to restart properly**:

| Platform         | Action                                                  |
| ---------------- | ------------------------------------------------------- |
| macOS Terminal   | Press `Ctrl+C` to exit, then run `claude` again         |
| VS Code Terminal | Close the terminal tab, open new terminal, run `claude` |
| iTerm2           | `Cmd+W` to close tab, open new tab, run `claude`        |

⚠️ **Common mistake**: Starting a new session with `/clear` does NOT reload hooks. You must exit the CLI entirely.

## Step 4: Verify Installation

After restarting, verify everything is set up correctly:

```bash
/ralph:hooks status
```

**Expected output** (all checks should pass):

```
=== Ralph Hooks Preflight Check ===

Plugin Location:
  ✓ Found at: ~/.claude/plugins/cache/cc-skills/ralph/X.X.X

Dependencies:
  ✓ jq X.X
  ✓ uv X.X.X
  ✓ Python 3.11+

Hook Scripts:
  ✓ loop-until-done.py (executable)
  ✓ archive-plan.sh (executable)
  ✓ pretooluse-loop-guard.py (executable)

Hook Registration:
  ✓ 3 hook(s) registered in settings.json

Session Status:
  ✓ Hooks were installed before this session

=== Summary ===
All preflight checks passed!
Ralph is ready to use. Run: /ralph:start
```

**If any check fails**: See [Troubleshooting](#troubleshooting) below.

## Step 5: Navigate to Your Alpha Forge Project

Ralph is designed **exclusively for Alpha Forge** ML research workflows. For other projects, hooks will silently pass through.

```bash
# Exit Claude Code
Ctrl+C

# Navigate to your alpha-forge project
cd ~/path/to/alpha-forge

# Start Claude Code in the project
claude
```

**Detection**: Ralph automatically detects Alpha Forge projects by:

- `pyproject.toml` containing "alpha-forge" or "alpha_forge"
- `packages/alpha-forge-core/` directory exists
- `outputs/runs/` directory exists

## Step 6: Start the Ralph Loop

```bash
/ralph:start
```

**You'll be asked**:

1. **Preset selection**: Choose "Production Mode" (9 hours, 99 iterations) for real work, or "POC Mode" (10 min, 20 iterations) for testing.

2. **Focus file**: Ralph can track a specific plan file. Options:
   - "Use discovered file" — Ralph finds your active plan/ADR
   - "Specify different file" — You provide a path
   - "Run without focus" — 100% autonomous, no plan tracking

**For first-time users**: Choose POC Mode + "Run without focus" to test the setup.

## Step 7: Observe Ralph Working

Once started, Ralph will:

1. Work on tasks autonomously
2. Prevent Claude from stopping prematurely
3. Pivot to exploration when tasks complete
4. Continue until you stop it or limits are reached

**To check status**:

```bash
/ralph:status
```

**To stop the loop**:

```bash
/ralph:stop
```

**Emergency stop** (if Ralph seems stuck):

```bash
touch .claude/STOP_LOOP
```

---

## Quick Reference

| Command                                                | Purpose                                            |
| ------------------------------------------------------ | -------------------------------------------------- |
| `/ralph:hooks install`                                 | Register hooks (one-time)                          |
| `/ralph:hooks status`                                  | Verify installation                                |
| `/ralph:start`                                         | Begin autonomous loop                              |
| `/ralph:stop`                                          | End the loop                                       |
| `/ralph:status`                                        | Check loop state                                   |
| `/ralph:config [show\|edit\|reset\|set]`               | View/modify runtime config                         |
| `/ralph:encourage <phrase\|--list\|--clear\|--remove>` | Manage encouraged list (applies next iteration)    |
| `/ralph:forbid <phrase\|--list\|--clear\|--remove>`    | Manage forbidden list (HARD BLOCKS next iteration) |

> **Runtime configurable**: `/ralph:encourage`, `/ralph:forbid`, and `/ralph:config` work with or without an active Ralph loop. Changes apply on the next iteration.

---

## Troubleshooting

> **General marketplace issues?** For clone failures, network errors, or authentication problems during `claude plugin marketplace add` or `claude plugin install`, see [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md).

### "Hooks were installed AFTER this session started"

**Cause**: You ran `/ralph:start` without restarting after `/ralph:hooks install`.

**Fix**: Exit Claude Code completely (`Ctrl+C`), then relaunch with `claude`.

### "jq not found" or "uv not found"

**Fix**: Install missing dependencies:

```bash
brew install uv jq
```

### "Python 3.11+ required"

**Fix**: Install Python 3.11 or later:

```bash
mise use python@3.11
# or
brew install python@3.11
```

### "Not an Alpha Forge project" warning

**Cause**: Ralph detected your project isn't Alpha Forge. Hooks will silently pass through.

**Options**:

1. Navigate to an Alpha Forge project and restart
2. Continue anyway (Ralph will work but with generic behavior)

### "No focus file discovered"

**Cause**: Ralph couldn't find a plan file to track.

**Options**:

1. Specify one: `/ralph:start -f path/to/plan.md`
2. Run without focus: `/ralph:start --no-focus`

---

## Next Steps

- Read [README.md](./README.md) for full feature documentation
- Read [MENTAL-MODEL.md](./MENTAL-MODEL.md) for Alpha Forge research workflow
- Configure limits: `/ralph:config show` and `/ralph:config set <key>=<value>`
- Add guidance: `/ralph:encourage <phrase>` and `/ralph:forbid <phrase>`
- Remove guidance: `/ralph:encourage --remove` and `/ralph:forbid --remove` (interactive picker)

---

## Sources

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins) - Official plugin documentation
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) - Official hooks reference
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) - Getting started with hooks
