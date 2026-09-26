# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: Workstation setup no longer installs the bot or digest

**Trigger**: Phases 2 and 3 wrote a Telegram token into a laptop env file, generated launcher scripts and loaded launchd plists for a bot and digest that now run in a private Restate deployment. The laptop jobs were retired on 2026-09-24, and a second bot poller on the same token breaks the deployed one.

**Fix**: The wizard now covers only Gmail OAuth via a 1Password item, building the CLI from the committed lockfile (`bun install --frozen-lockfile && bun run build`), and proving access to the intended mailbox. It states that the deployment is provisioned through its own repository's runbook and links the plugin CLAUDE.md contract.

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
