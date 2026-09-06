---
status: superseded
superseded-date: 2026-09-05
date: 2025-12-07
decision-maker: Terry Li
consulted: [claude-code-guide, general-purpose, Explore]
research-method: multi-agent
clarification-iterations: 1
perspectives: [User Experience, Documentation]
---

> ⚠️ **SUPERSEDED 2026-09-05 (issue [#127](https://github.com/terrylica/cc-skills/issues/127))**: the command this ADR told `/itp:setup` to advertise — `/itp hooks`, later renamed `/itp:tether` — was deleted along with `plugins/itp/scripts/manage-hooks.sh`. Claude Code now auto-loads `plugins/itp-hooks/hooks/hooks.json`, so there is no post-setup installation step to point users at, and the injection it performed would have double-registered every shipped hook. See [`2025-12-07-itp-hooks-settings-installer.md`](./2025-12-07-itp-hooks-settings-installer.md) for the full reasoning. The "Next Steps" section of both setup skills now says that enabling the plugin is the installation.

# Add `/itp hooks` Reminder to Setup Command

**Design Spec**: [Implementation Spec](/docs/design/2025-12-07-setup-hooks-reminder/spec.md)

## Context

The `/itp:setup` command installs ITP workflow dependencies (graph-easy, semantic-release, etc.) but does not remind users about the `/itp:hooks` command. Since Claude Code only loads hooks from `~/.claude/settings.json` (not plugin.json), users must explicitly install hooks after setup.

Currently, setup.md ends with a Troubleshooting section without guiding users to the next logical step: configuring itp-hooks for enhanced workflow guidance.

### Before/After

```
 ⏮️ Before: Setup Without Hooks Guidance

         ╭──────────────────────╮
         │         User         │
         ╰──────────────────────╯
           │
           │
           ∨
         ┌──────────────────────┐
         │      /itp:setup      │
         └──────────────────────┘
           │
           │
           ∨
         ┌──────────────────────┐
         │ Install Dependencies │
         └──────────────────────┘
           │
           │
           ∨
         ┌──────────────────────┐
         │   Troubleshooting    │
         └──────────────────────┘
           │
           │
           ∨
         ╭──────────────────────╮
         │         End          │
         │   (no next steps)    │
         ╰──────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Setup Without Hooks Guidance"; flow: south; }
[ User ] { shape: rounded; }
[ /itp:setup ] -> [ Install Dependencies ]
[ Install Dependencies ] -> [ Troubleshooting ]
[ Troubleshooting ] -> [ End\n(no next steps) ] { shape: rounded; }
[ User ] -> [ /itp:setup ]
```

</details>

```
 ⏭️ After: Setup With Hooks Guidance

       ╭──────────────────────╮
       │         User         │
       ╰──────────────────────╯
         │
         │
         ∨
       ┌──────────────────────┐
       │      /itp:setup      │
       └──────────────────────┘
         │
         │
         ∨
       ┌──────────────────────┐
       │ Install Dependencies │
       └──────────────────────┘
         │
         │
         ∨
       ┌──────────────────────┐
       │   Troubleshooting    │
       └──────────────────────┘
         │
         │
         ∨
       ┌──────────────────────┐
       │      Next Steps      │
       └──────────────────────┘
         │
         │ reminder
         ∨
       ┌──────────────────────┐
       │      /itp:hooks      │
       └──────────────────────┘
         │
         │
         ∨
       ┌──────────────────────┐
       │    settings.json     │
       └──────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Setup With Hooks Guidance"; flow: south; }
[ User ] { shape: rounded; }
[ /itp:setup ] -> [ Install Dependencies ]
[ Install Dependencies ] -> [ Troubleshooting ]
[ Troubleshooting ] -> [ Next Steps ]
[ Next Steps ] -- reminder --> [ /itp:hooks ]
[ /itp:hooks ] -> [ settings.json ]
[ User ] -> [ /itp:setup ]
```

</details>

## Decision

Add a "Next Steps" section at the end of `/itp:setup` command (setup.md) using structured bullets format to remind users about the hooks command.

### Implementation

Append after the Troubleshooting section (line 252) in `plugins/itp/commands/setup.md`:

```markdown
---

## Next Steps

After setup completes, configure itp-hooks for enhanced workflow guidance:

1. **Check hook status**:
   /itp:hooks status

2. **Install hooks** (if not already installed):
   /itp:hooks install

### What hooks provide

- **PreToolUse guard**: Blocks Unicode box-drawing diagrams without source blocks
- **PostToolUse reminder**: Prompts ADR sync and graph-easy skill usage

**IMPORTANT:** Hooks require a Claude Code session restart after installation.
```

## Rationale

Research validated this approach:

1. **No native alternative**: Claude Code has no built-in mechanism to emit post-command reminders; content-based guidance is the only option
2. **Existing precedent**: hooks.md already uses "Post-Action Reminder" pattern (lines 38-44)
3. **Best practice alignment**: Addresses documented "babysitting problem" per community guides
4. **10+ reminder patterns** already exist in cc-skills codebase

### Format Choice

User selected **Structured bullets** format over:

- Simple bold text (hooks.md style) - too minimal for multi-step guidance
- Box-drawing ASCII (itp.md style) - overkill for utility command

## Architecture

```
                                        🏗️ Setup Command Flow Architecture

┌──────────┐     ┌────────────┐     ┌────────────┐     ┌─────────────────┐     ┌───────────────┐     ╔═════════════╗
│ setup.md │     │ Next Steps │     │ /itp:hooks │     │ manage-hooks.sh │     │ settings.json │     ║ Claude Code ║
│          │ ──> │  Section   │ ──> │            │ ──> │                 │ ──> │               │ ──> ║   Session   ║
└──────────┘     └────────────┘     └────────────┘     └─────────────────┘     └───────────────┘     ╚═════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Setup Command Flow Architecture"; flow: east; }
[ setup.md ] -> [ Next Steps\nSection ] -> [ /itp:hooks ]
[ /itp:hooks ] -> [ manage-hooks.sh ]
[ manage-hooks.sh ] -> [ settings.json ]
[ settings.json ] -> [ Claude Code\nSession ] { border: double; }
```

</details>

## Consequences

### Positive

- Users are guided to install hooks after setup completes
- Reduces support friction from users not knowing about hooks
- Consistent with existing reminder patterns in codebase

### Negative

- Adds ~20 lines to setup.md (minimal bloat)

### Neutral

- Hooks still require manual installation (by design - explicit user consent)
