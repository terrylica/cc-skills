# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-03-02: Merged firecrawl-self-hosted into this skill

**What**: Absorbed `firecrawl-self-hosted` skill — its SKILL.md condensed into `self-hosted-operations.md` reference, and its 3 reference docs (bootstrap-guide, best-practices, troubleshooting) moved here.

**Why**: The two skills covered the same service (self-hosted Firecrawl). Consolidation eliminates skill discovery friction — one skill for all Firecrawl concerns.

**Files added**:

- `references/self-hosted-operations.md` (new — condensed from old SKILL.md)
- `references/self-hosted-bootstrap-guide.md` (moved + renamed)
- `references/self-hosted-best-practices.md` (moved + renamed)
- `references/self-hosted-troubleshooting.md` (moved + renamed)

**Files modified**:

- `SKILL.md` — added self-hosted triggers, Section 5, updated references, removed scope boundary note

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
