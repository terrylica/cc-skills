# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: Health checks what this machine actually owns

**Trigger**: Checks 4 to 8 inspected a local bot PID file, a local digest PID file, local launchd jobs, `/tmp` circuit breakers and a local audit directory, all belonging to the laptop jobs retired on 2026-09-24. On a correctly migrated machine every one of them reported "not running", which reads as an outage when it is the healthy state.

**Fix**: The check now covers the CLI binary and its committed lockfile, the interactive CLI's variables, 1Password, the token cache (names only), whether `scripts/bot.ts` still exports `buildBot()` (the deployment's contract), a pointer to `/status` for the deployed bot, and a retired-jobs check whose healthy result is "none".

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
