# Ralph Universal

Autonomous loop mode for **any project** - a surgical fork of Ralph with the Alpha-Forge exclusivity removed.

## What This Is

Ralph Universal is a direct clone of the Ralph plugin with **one surgical edit**: the Alpha-Forge exclusivity guard has been removed from `loop-until-done.py`.

| Feature              | Ralph           | Ralph Universal      |
| -------------------- | --------------- | -------------------- |
| Alpha-Forge projects | ✅ Full support | ✅ Full support      |
| Other projects       | ❌ Skipped      | ✅ Works             |
| Hooks                | Same            | Same                 |
| Commands             | 8 commands      | 3 commands (minimal) |

## Why This Exists

Ralph was designed specifically for Alpha-Forge ML research workflows with metrics-based convergence detection. Rather than modifying the production Ralph, this fork provides a controlled experiment for general project support.

See: [Issue #12](https://github.com/terrylica/cc-skills/issues/12)

## Quick Start

```bash
# Install hooks
/ralph-universal:hooks install

# Restart Claude Code (hooks only load at startup)

# Start the loop
/ralph-universal:start --poc

# Stop the loop
/ralph-universal:stop
```

## Commands

| Command                   | Description                                  |
| ------------------------- | -------------------------------------------- |
| `/ralph-universal:start`  | Enable loop mode (POC or Production presets) |
| `/ralph-universal:stop`   | Disable loop mode immediately                |
| `/ralph-universal:status` | Show current state                           |

## Differences from Ralph

1. **No Alpha-Forge guard** - Works on any project
2. **Simplified commands** - Only start/stop/status (no guidance, forbid, encourage)
3. **Separate state files** - Uses `ralph-universal-state.json` (won't conflict with Ralph)
4. **No metrics-based convergence** - Uses time/iteration limits only

## State Files

| File                                  | Purpose                         |
| ------------------------------------- | ------------------------------- |
| `.claude/ralph-universal-state.json`  | Current loop state              |
| `.claude/ralph-universal-config.json` | Loop configuration              |
| `.claude/STOP_LOOP`                   | Kill switch (shared with Ralph) |

## When to Use

- **Use Ralph** for Alpha-Forge ML research workflows
- **Use Ralph Universal** for general projects needing autonomous validation

## Related

- [Ralph Plugin](../ralph/README.md) - Original Alpha-Forge-only version
- [Issue #12](https://github.com/terrylica/cc-skills/issues/12) - Feature request for generic support
