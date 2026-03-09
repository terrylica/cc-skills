# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-03-09: Production Learnings from opendeviationbar v13.2.0 Release

**Status**: Major update — 3 new sections added from real-world release failure.

### What Changed

- Added **Step 0: Pre-Release Sync** — mandatory `git pull origin main` before any release
- Added **Known Issue: `@semantic-release/git` Untracked File Explosion** — `git ls-files -m -o` missing `--exclude-standard` crashes plugin with ~100MB stdout in repos with `.venv/`
- Added **Partial Semantic-Release Recovery** — manual tag creation when semantic-release partially succeeds
- Added **Post-Release Deploy Reminder** — prevents version drift on production hosts
- Added 3 new error recovery rows for semantic-release-specific failures

### Why It Changed

During the opendeviationbar v13.2.0 release:

1. `@semantic-release/git` v10.0.1 crashed listing 100K+ gitignored `.venv/` files (upstream bugs: #345, #347, #107)
2. Semantic-release partially ran (bumped Cargo.toml + CHANGELOG.md) but failed before creating tag — required manual recovery
3. Forgot to pull remote changes before release, causing diverged branch confusion
4. Forgot to deploy to gpu-host after PyPI publish, causing 30+ minutes of version drift alerts

### Files Affected

- `SKILL.md`: +80 lines (Step 0, Known Issue, Partial Recovery, Deploy Reminder, error table rows)
- `references/evolution-log.md`: This entry

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
