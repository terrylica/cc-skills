# Content Deduplication Analysis

> Task 6: Content Deduplication Analysis — Investigate duplicated/orphaned content across the cc-skills documentation ecosystem.

**Date**: 2026-03-02  
**Task**: task-6  
**Agent**: OakHawk

---

## Executive Summary

This analysis identifies duplicated content, orphaned documentation, and structural inconsistencies across the cc-skills CLAUDE.md files and docs directory. The findings reveal several categories of duplication and a small number of truly orphaned files.

---

## 1. Common Text Patterns (Duplication)

### 1.1 Hub+Sibling Navigation Links

**Pattern**: `**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)`

| Variant | Count | Plugins |
|---------|-------|---------|
| `Hub + Sibling (itp-hooks)` | 5 | asciinema-tools, quality-tools, statusline-tools, doc-tools, ru |
| `Hub + Sibling (itp)` | 3 | link-tools, rust-tools, git-town-workflow |
| `Hub + Sibling (gh-tools)` | 3 | devops-tools, gitnexus-tools, dotfiles-tools |
| `Hub + Sibling (gmail-commander)` | 2 | calcom-commander, tts-tg-sync |
| `Hub only` | 1 | kokoro-tts (missing Sibling) |

**Finding**: All 23 plugin CLAUDE.md files follow the Hub+Sibling pattern with minor variations. The **kokoro-tts** plugin is missing the Sibling link entirely.

### 1.2 1Password Documentation (Duplicated)

Multiple plugins include similar 1Password documentation:

| Plugin | Content |
|--------|---------|
| calcom-commander | `CALCOM_OP_UUID` reference |
| devops-tools | Full vault-first rule, service account token, credential patterns |
| gmail-commander | OAuth token caching from 1Password |
| itp-hooks | References |
| mise | References |

**Recommendation**: Extract 1Password patterns to a shared reference document or skill.

### 1.3 Skills Section Inconsistency

| Status | Count |
|--------|-------|
| Has Skills section | 19/23 plugins |
| Missing Skills section | 7 plugins |

Missing Skills: calcom-commander, git-town-workflow, gmail-commander, kokoro-tts, mise, ru, tts-tg-sync

### 1.4 Commands Section Inconsistency

| Status | Count |
|--------|-------|
| Has Commands section | 7/23 plugins |
| Missing Commands section | 16 plugins |

### 1.5 Dependencies/Tools Section Inconsistency

| Status | Count |
|--------|-------|
| Has Dependencies/Tools | 3/23 plugins |
| Missing Dependencies/Tools | 20 plugins |

---

## 2. Orphaned Documentation

### 2.1 Truly Orphaned Files (Never Linked)

| File | Last Modified | Notes |
|------|---------------|-------|
| `docs/tool-inventory.md` | Mar 2, 2026 | Recently created, no links found |
| `docs/adr/2025-12-13-itp-hooks-file-tree-detection.md` | Dec 13, 2025 | Never linked from anywhere |
| `docs/design/2025-12-10-clickhouse-skill-documentation-gaps/spec.md` | Dec 10, 2025 | Design spec never linked |

### 2.2 Orphan Analysis

- **tool-inventory.md**: Created Mar 2, 2026 (today) — appears to be a new file that hasn't been integrated into the documentation hierarchy
- **itp-hooks-file-tree-detection.md**: Created Dec 13, 2025 — no references found in any CLAUDE.md, README, or other docs
- **clickhouse-skill-documentation-gaps/spec.md**: Design spec with no incoming links

---

## 3. Content Freshness Mapping

### 3.1 Plugin CLAUDE.md Files

| Date | Count | Files |
|------|-------|-------|
| Feb 25, 2026 | 16 | Most plugins recently updated |
| Feb 28, 2026 | 3 | gh-tools, statusline-tools, asciinema-tools |
| Mar 2, 2026 | 1 | mise (just updated) |
| Mar 2, 2026 | 1 | tool-inventory.md (newly created) |

### 3.2 Documentation Files (Last 10 Modified)

| Date | File |
|------|------|
| Jan 31, 2026 | adr/2026-01-22-polars-preference-hook.md |
| Jan 30, 2026 | adr/2026-01-15-mise-env-token-loading-patterns.md |
| Jan 30, 2026 | design/2026-01-18-sred-dynamic-discovery/spec.md |
| Jan 30, 2026 | RELEASE.md |
| Feb 28, 2026 | adr/2026-01-11-gh-issue-body-file-guard.md |
| Feb 28, 2026 | HOOKS.md |
| Feb 25, 2026 | CLAUDE.md, LESSONS.md |
| Feb 23, 2026 | cargo-tty-suspension-prevention.md |

---

## 4. Duplicate Information Patterns

### 4.1 Plugin Count Inconsistencies

| Source | Count | Issue |
|--------|-------|-------|
| Root CLAUDE.md | 20 plugins | Outdated |
| plugins/CLAUDE.md | 21 plugins | Lists "all 21" but should be 23 |
| marketplace.json | 23 plugins | Current SSoT |

**Finding**: Root CLAUDE.md says "20 plugins" but there are 23. The plugins/CLAUDE.md says "21 plugins" but should say "23".

### 4.2 Repeated Documentation Conventions

- **Bun-first policy**: Mentioned in root CLAUDE.md, repeated in itp/CLAUDE.md
- **SSoT principles**: Scattered across multiple CLAUDE.md files
- **GitHub Actions policy**: Duplicated in gh-tools and root CLAUDE.md
- **mise usage**: Multiple plugins reference mise but with varying levels of detail

### 4.3 Structural Inconsistencies

| Section | Present In | Missing From |
|---------|------------|--------------|
| Overview | 9 plugins | 14 plugins |
| Architecture | 6 plugins | 17 plugins |
| Dependencies | 3 plugins (itp, gh-tools, kokoro-tts) | 20 plugins |

---

## 5. Deduplication Recommendations

### 5.1 High Priority

1. **Add Sibling link to kokoro-tts/CLAUDE.md**
   - Missing: `| **Sibling**: [tts-tg-sync CLAUDE.md](../tts-tg-sync/CLAUDE.md)`

2. **Delete or integrate orphaned files**
   - `docs/tool-inventory.md` — integrate into docs/ or delete if unnecessary
   - `docs/adr/2025-12-13-itp-hooks-file-tree-detection.md` — link from itp-hooks or delete
   - `docs/design/2025-12-10-clickhouse-skill-documentation-gaps/spec.md` — link from devops-tools or delete

3. **Fix plugin count in root CLAUDE.md**
   - Change "20 plugins" to "23 plugins"
   - Update directory structure section accordingly

4. **Fix plugin count in plugins/CLAUDE.md**
   - Change "all 21" to "all 23"

### 5.2 Medium Priority

5. **Create shared 1Password reference**
   - Extract common patterns from calcom-commander, devops-tools, gmail-commander
   - Place in a shared location (e.g., docs/security-credentials.md)

6. **Standardize CLAUDE.md structure**
   - Define minimum required sections: Overview, Skills, Commands, Dependencies
   - Create template for plugin CLAUDE.md files

7. **Add Skills section to missing plugins**
   - calcom-commander, git-town-workflow, gmail-commander, kokoro-tts, mise, ru, tts-tg-sync

### 5.3 Low Priority

8. **Consolidate repeated content**
   - Bun-first policy: reference root instead of duplicating
   - SSoT principles: create dedicated doc
   - GitHub Actions policy: reference instead of duplicate

---

## 6. Summary Statistics

| Metric | Value |
|--------|-------|
| Total CLAUDE.md files (non-node_modules) | 26 |
| Total docs/*.md files | 90+ |
| Orphaned files identified | 3 |
| Plugins missing Sibling link | 1 (kokoro-tts) |
| Plugins missing Skills section | 7 |
| Plugins missing Commands section | 16 |
| Plugins missing Dependencies section | 20 |
| Plugin count inconsistencies | 2 (root, plugins/CLAUDE.md) |

---

## Appendix: Files Analyzed

### Plugin CLAUDE.md Files (23)

```
plugins/asciinema-tools/CLAUDE.md
plugins/calcom-commander/CLAUDE.md
plugins/devops-tools/CLAUDE.md
plugins/doc-tools/CLAUDE.md
plugins/dotfiles-tools/CLAUDE.md
plugins/gh-tools/CLAUDE.md
plugins/git-town-workflow/CLAUDE.md
plugins/gitnexus-tools/CLAUDE.md
plugins/gmail-commander/CLAUDE.md
plugins/itp-hooks/CLAUDE.md
plugins/itp/CLAUDE.md
plugins/kokoro-tts/CLAUDE.md
plugins/link-tools/CLAUDE.md
plugins/mise/CLAUDE.md
plugins/mql5/CLAUDE.md
plugins/plugin-dev/CLAUDE.md
plugins/productivity-tools/CLAUDE.md
plugins/quality-tools/CLAUDE.md
plugins/quant-research/CLAUDE.md
plugins/ru/CLAUDE.md
plugins/rust-tools/CLAUDE.md
plugins/statusline-tools/CLAUDE.md
plugins/tts-tg-sync/CLAUDE.md
```

### Root Documentation

```
CLAUDE.md
docs/CLAUDE.md
docs/*.md (10 files)
docs/adr/*.md (40+ files)
docs/design/*.md (40+ files)
```
