# Ralph Universal

Autonomous loop mode for **any project** - a surgical fork of Ralph with the research-repo exclusivity removed.

## What This Is

Ralph Universal is a surgical fork of Ralph with research-repo exclusivity removed. Key changes:

- Removed research-repo guards from `loop-until-done.py`, `pretooluse-loop-guard.py`, `archive-plan.sh`
- Created `UniversalAdapter` that works on ANY project (time/iteration-based completion)
- Generalized `ralph-unified.md` template (removed research-repo specific metrics/protocols)
- Updated adapter registry to use universal fallback

| Feature              | Ralph           | Ralph Universal |
| -------------------- | --------------- | --------------- |
| research-repo projects | ✅ Full support | ✅ Full support |
| Other projects       | ❌ Skipped      | ✅ Works        |
| Hooks                | Same            | Same            |
| Commands             | 8 commands      | 6 commands      |

## Why This Exists

Ralph was designed specifically for research-repo ML research workflows with metrics-based convergence detection. Rather than modifying the production Ralph, this fork provides a controlled experiment for general project support.

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

| Command                      | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `/ralph-universal:start`     | Enable loop mode (POC or Production presets) |
| `/ralph-universal:stop`      | Disable loop mode immediately                |
| `/ralph-universal:status`    | Show current state                           |
| `/ralph-universal:forbid`    | Add item to forbidden list                   |
| `/ralph-universal:encourage` | Add item to encouraged list                  |
| `/ralph-universal:hooks`     | Install/uninstall hooks                      |

## Configuring Guidance

Control what the loop works on using forbid/encourage:

```bash
# Add items to work on
/ralph-universal:encourage test coverage
/ralph-universal:encourage documentation

# Block certain work
/ralph-universal:forbid refactoring
/ralph-universal:forbid dependency updates

# List current configuration
/ralph-universal:forbid --list
/ralph-universal:encourage --list

# Clear all
/ralph-universal:forbid --clear
```

Configuration is stored in `.claude/ralph-config.json` and applies on the next iteration.

## Differences from Ralph

1. **No research-repo guard** - Works on any project type
2. **Universal adapter fallback** - Uses `UniversalAdapter` when no specific adapter matches
3. **Generic template** - `ralph-unified.md` uses project-agnostic discovery protocol
4. **Separate state files** - Uses `ralph-universal-state.json` (won't conflict with Ralph)
5. **Time/iteration-based completion** - No metrics-based convergence for universal projects

## State Files

| File                                  | Purpose                           |
| ------------------------------------- | --------------------------------- |
| `.claude/ralph-universal-state.json`  | Current loop state                |
| `.claude/ralph-universal-config.json` | Loop configuration                |
| `.claude/ralph-config.json`           | Guidance (forbid/encourage lists) |
| `.claude/STOP_LOOP`                   | Kill switch (shared with Ralph)   |

## When to Use

- **Use Ralph** for research-repo ML research workflows
- **Use Ralph Universal** for general projects needing autonomous validation

## Related

- [Ralph Plugin](../ralph/README.md) - Original research-repo-only version
- [Issue #12](https://github.com/terrylica/cc-skills/issues/12) - Feature request for generic support
