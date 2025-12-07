---
status: accepted
date: 2025-12-07
decision-maker: Terry Li
consulted: [Claude Code]
research-method: single-agent
clarification-iterations: 2
perspectives: [User-Experience, Reliability, Maintainability]
---

# ITP Hooks Settings Installer

**Design Spec**: [Implementation Spec](/docs/design/2025-12-07-itp-hooks-settings-installer/spec.md)

## Context and Problem Statement

Claude Code only loads hooks from `~/.claude/settings.json`, NOT from plugin.json files. The itp-hooks plugin defines hooks in `hooks.json`, but these are never invoked by Claude Code because the runtime only reads hooks from the user's settings file.

Users need a way to install/uninstall itp-hooks to their settings.json without manually editing JSON.

<!-- graph-easy source: before-after
[Plugin hooks.json] -- ignored --> [Claude Code Runtime]

[settings.json hooks] -- loaded --> [Claude Code Runtime]
-->

```
+-------------------+  ignored   +---------------------+
| Plugin hooks.json | ---------> | Claude Code Runtime |
+-------------------+            +---------------------+
                                           ^
                                           |
                                         loaded
                                           |
+---------------------+                    |
| settings.json hooks | -------------------+
+---------------------+
```

## Decision Drivers

- **Reliability**: Must not corrupt settings.json under any circumstance
- **Idempotency**: Running install twice should not create duplicates
- **Recoverability**: Users must be able to undo changes easily
- **Discoverability**: Status command shows current state clearly

## Considered Options

1. Manual JSON editing instructions
2. Slash command with shell script (`/itp hooks`)
3. Automatic installation on plugin enable

## Decision Outcome

Chosen option: **Slash command with shell script** (`/itp hooks`)

### Consequences

- Good: User control over when hooks are installed
- Good: Explicit backup/restore functionality
- Good: Idempotent operations (safe to run multiple times)
- Neutral: Requires jq dependency
- Bad: Extra step after plugin installation

## Architecture

<!-- graph-easy source: architecture
[/itp hooks command] -> [manage-hooks.sh]
[manage-hooks.sh] -> [jq]
[jq] -> [settings.json]
[manage-hooks.sh] -> [~/.claude/backups/]
-->

```
+-------------------+     +------------------+     +-----+     +---------------+
| /itp hooks command| --> | manage-hooks.sh  | --> | jq  | --> | settings.json |
+-------------------+     +------------------+     +-----+     +---------------+
                                   |
                                   |
                                   v
                          +-------------------+
                          | ~/.claude/backups/|
                          +-------------------+
```

### Components

| Component            | Purpose                      |
| -------------------- | ---------------------------- |
| `hooks.md`           | Slash command entry point    |
| `manage-hooks.sh`    | Idempotent JSON manipulation |
| `~/.claude/backups/` | Timestamped settings backups |

## Decision Log

| Date       | Decision                    | Rationale                                                                 |
| ---------- | --------------------------- | ------------------------------------------------------------------------- |
| 2025-12-07 | Use `$HOME` literal in JSON | settings.json doesn't support `${CLAUDE_PLUGIN_ROOT}`                     |
| 2025-12-07 | Numbered restore list       | Users forget timestamps; numbered list with `restore latest` is better UX |
| 2025-12-07 | Atomic writes via temp+mv   | Prevents corruption from interrupted writes                               |

## More Information

- [Idempotent Bash Scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- [jq best practices](https://unix.stackexchange.com/questions/721970/can-i-use-jq-to-prettify-a-file-in-place)
