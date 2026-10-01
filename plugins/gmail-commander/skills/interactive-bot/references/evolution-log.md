# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: Describe the deployed bot instead of a local daemon

**Trigger**: "Running Manually" told agents to start `scripts/bot.ts` from a laptop directory, which now competes with the deployed Restate tenant for the bot token. The command table also omitted `/abort`, and the References section linked three files that never existed.

**Fix**: Added where the bot runs and the one-consumer-per-token warning, a preflight that checks `buildBot` is still exported, `/abort` in the command table, and a source map pointing at the real files in place of the missing references.

**Files**: `SKILL.md`

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
