**Skill**: [Skill Architecture](../SKILL.md)

# Command-Skill Duality

Plugins can expose functionality through both **commands** (slash-invoked) and **skills** (organically triggered). This reference explains when to use each and how they complement each other.

---

## Commands vs Skills

| Aspect      | Commands (`commands/*.md`)                      | Skills (`skills/*/SKILL.md`)                 |
| ----------- | ----------------------------------------------- | -------------------------------------------- |
| Invocation  | Explicit: `/plugin:command`                     | Organic: conversation trigger keywords       |
| Discovery   | User must know the command name                 | Claude matches description against context   |
| Frontmatter | `description`, `allowed-tools`, `argument-hint` | `name`, `description`, `allowed-tools`       |
| Best for    | Direct, imperative actions                      | Contextual, multi-phase workflows            |
| Loading     | On-demand when slash-invoked                    | When description keywords match conversation |
| Complexity  | Typically thin (delegates to skills or scripts) | Full workflow with phases and references     |

---

## When to Use Commands

Commands are the right choice for:

- **Direct operational actions**: `/setup`, `/health`, `/hooks install`
- **Quick-access entry points**: User knows exactly what they want
- **Management operations**: Install, uninstall, status, start, stop
- **Argument-driven actions**: `/command arg1 arg2` where arguments are known upfront
- **Thin wrappers**: Delegate complex logic to a skill or script

**Example**: A `/health` command that runs a quick 10-check diagnostic sweep.

---

## When to Use Skills

Skills are the right choice for:

- **Multi-phase workflows**: Bootstrap with preflight, execute, verify
- **Diagnostic/troubleshooting**: Symptoms vary, requires investigation
- **Configuration management**: Contextual editing based on current state
- **Complex operations**: Upgrade with before/after health checks
- **Domain knowledge**: Skill body provides context Claude needs to help

**Example**: A `diagnostic-issue-resolver` skill that collects symptoms, runs diagnostics, identifies root cause, and applies fixes.

---

## Complementary Pattern

Commands and skills can cover the same domain with different entry points:

```
Command: Quick-access, deterministic, user-initiated
  └── /plugin:health  →  Run 10 checks, print table

Skill: Full-featured, contextual, conversation-triggered
  └── system-health-check  →  Phased workflow with diagnostics and recommendations
```

The command provides a fast path for users who know what they want. The skill provides a guided experience when the user describes a problem or need.

---

## Plugin Layout with Both

```
my-plugin/
├── commands/
│   ├── setup.md           # /plugin:setup - bootstrap entry point
│   ├── health.md          # /plugin:health - quick diagnostic sweep
│   └── hooks.md           # /plugin:hooks - hook management (install/uninstall/status)
├── skills/
│   ├── full-stack-bootstrap/    # Triggered by "setup", "install", "bootstrap"
│   │   ├── SKILL.md
│   │   └── references/
│   ├── system-health-check/     # Triggered by "health check", "diagnostics"
│   │   ├── SKILL.md
│   │   └── references/
│   ├── service-process-control/ # Triggered by "start", "stop", "restart"
│   │   ├── SKILL.md
│   │   └── references/
│   └── settings-and-tuning/     # Triggered by "settings", "configure"
│       ├── SKILL.md
│       └── references/
├── hooks/
│   ├── hooks.json               # Hook registration
│   └── event-handler.ts         # Hook implementation
└── scripts/
    └── lib/                     # Shared library (sourced by scripts)
```

---

## Design Guidelines

1. **Commands should be thin** - Delegate complex logic to skills or scripts. A command body should rarely exceed 50 lines.
2. **Skills should be self-contained** - Work without the command. A user who describes the problem in conversation should get the same quality of help.
3. **Use `argument-hint` in commands** - Help users discover available arguments (e.g., `argument-hint: install | uninstall | status`).
4. **Commands for "I know what I want"** - Direct actions, known operations.
5. **Skills for "help me figure it out"** - Guided workflows, diagnostics, configuration.
6. **Overlap is intentional** - The same domain can have both a command and a skill without conflict.

---

## Hook Commands

A special case: the **hooks management command** (`/plugin:hooks`).

Most plugins with hooks should provide a command for managing them:

```
/plugin:hooks install    → Register hooks in settings.json
/plugin:hooks uninstall  → Remove hooks from settings.json
/plugin:hooks status     → Show current hook state
```

This command reads `hooks.json` from the plugin's `hooks/` directory and integrates with `~/.claude/settings.json`. Use AskUserQuestion to present install/uninstall/status options when no argument is provided.

---

## Choosing the Right Mix

| Plugin Type                 | Commands | Skills | Hooks |
| --------------------------- | -------- | ------ | ----- |
| Simple tool                 | 0-1      | 1-2    | 0     |
| Workflow automation         | 1-2      | 2-4    | 0-1   |
| Multi-component integration | 2-3      | 4-8    | 1-2   |
| Knowledge repository        | 0        | 1-3    | 0     |

Simple plugins may need only skills. Complex integrations benefit from the full complement of commands, skills, and hooks working together.
