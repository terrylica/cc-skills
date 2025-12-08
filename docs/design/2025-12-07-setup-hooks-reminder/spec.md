---
adr: 2025-12-07-setup-hooks-reminder
source: ~/.claude/plans/polymorphic-conjuring-glade.md
implementation-status: in_progress
phase: phase-1
last-updated: 2025-12-07
---

# Implementation Spec: Add `/itp hooks` Reminder to Setup Command

**ADR**: [Add `/itp hooks` Reminder to Setup Command](/docs/adr/2025-12-07-setup-hooks-reminder.md)

## Summary

Add a "Next Steps" section at the end of `/itp:setup` to remind users about the `/itp:hooks` command for checking status and installing hooks.

## Research Validation

**Confirmed sensible and feasible:**

- No native reminder mechanism in Claude Code - content-based guidance is the only option
- Markdown rendering fully supported (bold, code blocks, headers)
- Existing precedent: hooks.md uses "Post-Action Reminder" pattern
- Addresses documented "babysitting problem" per community guides
- 10+ reminder patterns already exist in cc-skills codebase

## File to Modify

`/Users/terryli/eon/cc-skills/plugins/itp/commands/setup.md`

## Implementation Tasks

### Task 1: Add Next Steps Section

Append after line 252 (after Troubleshooting section) using **Structured bullets** format:

````markdown
---

## Next Steps

After setup completes, configure itp-hooks for enhanced workflow guidance:

1. **Check hook status**:
   ```bash
   /itp:hooks status
   ```
````

1. **Install hooks** (if not already installed):

   ```bash
   /itp:hooks install
   ```

### What hooks provide

- **PreToolUse guard**: Blocks Unicode box-drawing diagrams without `<details>` source blocks
- **PostToolUse reminder**: Prompts ADR sync and graph-easy skill usage

**IMPORTANT:** Hooks require a Claude Code session restart after installation.

```

## Success Criteria

- [ ] Next Steps section appended to setup.md after Troubleshooting
- [ ] Section uses structured bullets format (numbered steps with code blocks)
- [ ] Includes explanation of what hooks provide
- [ ] Includes IMPORTANT restart reminder
- [ ] Markdown renders correctly

## Rationale

- **Structured bullets** format chosen for clear hierarchy and numbered steps
- Follows existing patterns from itp.md and hooks.md
- Provides actionable commands users can copy-paste
- Explains value proposition (what hooks do)
- Includes critical restart requirement
```
