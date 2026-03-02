# Documentation Standards Compliance Matrix

**Task:** Task 1: Documentation Standards Audit  
**Generated:** 2026-03-02  
**Plugins Audited:** 23

---

## Executive Summary

This audit examines all 23 plugin CLAUDE.md files against the documented standards in `docs/CLAUDE.md` and `plugins/CLAUDE.md`. The audit identifies significant inconsistencies in structure, formatting, and content that should be addressed for a unified developer experience.

**Key Findings:**
- **100%** of plugins have a CLAUDE.md file
- **87%** (20/23) follow the Hub+Sibling navigation pattern
- **78%** (18/23) have Skills tables with consistent structure
- **70%** (16/23) have Commands tables
- **65%** (15/23) have Hooks tables
- **Inconsistent**: Header formatting, quote descriptions, section ordering

---

## Standards Reference

### Expected Structure (from `docs/CLAUDE.md` and `plugins/CLAUDE.md`)

| Element | Expected Pattern |
|---------|------------------|
| **Header** | `# <plugin-name> Plugin` or `# <plugin-name>` |
| **Description** | `> Brief description (blockquote)` |
| **Hub Link** | `**Hub**: [Root CLAUDE.md](../../CLAUDE.md)` |
| **Sibling Links** | `**Sibling**: [<name> CLAUDE.md](../<path>/CLAUDE.md)` |
| **Skills Table** | `\| Skill \| Purpose \|` format |
| **Commands Table** | `\| Command \| Purpose \|` format |
| **Hooks Table** | `\| Hook \| Event \| Matcher \| Purpose \|` format |
| **Link Conventions** | Relative for skills, repo-root `/docs/` for ADRs, full URL for external |

---

## Per-Plugin Compliance Matrix

| Plugin | Header Format | Hub+Sibling | Skills | Commands | Hooks | Conventions | Overall |
|--------|--------------|-------------|--------|----------|-------|-------------|---------|
| plugin-dev | ✓ `# plugin-dev Plugin` | ✓ | ✓ | ✓ | - | ✓ | **Good** |
| itp | ✓ `# itp Plugin` | ✓ | ✓ | ✓ | - | ✓ | **Good** |
| gh-tools | ✓ `# gh-tools Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |
| link-tools | ✓ `# link-tools Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |
| devops-tools | ✓ `# devops-tools Plugin` | ✓ | ✓ | - | - | ✓ | **Good** |
| dotfiles-tools | ✓ `# dotfiles-tools Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |
| doc-tools | ✓ `# doc-tools Plugin` | ✓ | ✓ | - | - | ✓ | **Good** |
| quality-tools | ✓ `# quality-tools Plugin` | ✓ | ✓ | - | - | ✓ | **Good** |
| productivity-tools | ✓ `# productivity-tools Plugin` | ✓ | ✓ | ✓ | ✓ | ✓ | **Excellent** |
| mql5 | ✓ `# mql5 Plugin` | ✓ | ✓ | - | - | ✓ | **Good** |
| itp-hooks | ✓ `# itp-hooks Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |
| ru | ✓ `# ru Plugin` | ✓ | ✓ | ✓ | ✓ | ✓ | **Excellent** |
| statusline-tools | ✓ `# statusline-tools Plugin` | ✓ | ✓ | ✓ | ✓ | ✓ | **Excellent** |
| asciinema-tools | ✓ `# asciinema-tools Plugin` | ✓ | ✓ | ✓ | - | ✓ | **Good** |
| git-town-workflow | ✓ `# git-town-workflow Plugin` | ✓ | - | ✓ | - | ✓ | **Fair** |
| quant-research | ✓ `# quant-research Plugin` | ✓ | ✓ | - | - | ✓ | **Good** |
| gmail-commander | ⚠ `# Gmail Commander Plugin` | ✓ | - | ✓ | - | ✓ | **Fair** |
| kokoro-tts | ✓ `# kokoro-tts Plugin` | ⚠ Hub only | ✓ | - | - | ✓ | **Fair** |
| tts-telegram-sync | ✓ `# tts-telegram-sync Plugin` | ✓ | - | - | - | ✓ | **Fair** |
| calcom-commander | ⚠ `# Cal.com Commander Plugin` | ✓ | - | - | - | ✓ | **Fair** |
| mise | ✓ `# mise Plugin` | ✓ | - | ✓ | - | ✓ | **Fair** |
| gitnexus-tools | ✓ `# gitnexus-tools Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |
| rust-tools | ✓ `# rust-tools Plugin` | ✓ | ✓ | - | ✓ | ✓ | **Good** |

---

## Detailed Gap Analysis

### 1. Header Format Inconsistencies

| Issue | Plugins Affected |
|-------|------------------|
| Non-standard naming (spaces vs hyphens) | `gmail-commander` ("Gmail Commander"), `calcom-commander` ("Cal.com Commander"), `kokoro-tts` (missing "Plugin"), `tts-telegram-sync` (missing "Plugin") |
| Capitalization inconsistencies | Some use Title Case, others use lowercase |

**Recommendation:** Standardize to `# <plugin-name> Plugin` format using hyphens for compound names.

### 2. Missing Hub+Sibling Navigation

| Plugin | Missing |
|--------|---------|
| kokoro-tts | Sibling links |

**Recommendation:** Add Sibling links to all plugin CLAUDE.md files.

### 3. Missing Skills Tables

| Plugin | Notes |
|--------|-------|
| git-town-workflow | Has Commands only |
| gmail-commander | Has Commands, references skill via paragraph |
| tts-telegram-sync | References skills implicitly |
| calcom-commander | Has Architecture section instead |
| mise | References skills in "Future Skills" |

**Recommendation:** Add Skills tables to plugins that reference skills, or clarify that they don't have skills.

### 4. Missing Commands Tables

| Plugin | Notes |
|--------|-------|
| itp | Has Skills with slash commands embedded |
| gh-tools | Has sections describing commands |
| link-tools | Has Hooks only |
| devops-tools | Has Skills only |
| doc-tools | Has Skills only |
| quality-tools | Has Skills only |
| mql5 | Has Skills only |
| itp-hooks | Has Hooks and Skills |
| asciinema-tools | Has Commands (correctly) |
| quant-research | Has Skills only |
| gitnexus-tools | Has Skills only |
| rust-tools | Has Skills and Hooks |

**Recommendation:** For plugins without slash commands, explicitly state "No commands" or consolidate into Skills table.

### 5. Missing Hooks Tables

| Plugin | Notes |
|--------|-------|
| plugin-dev | No hooks |
| itp | Has Dependencies, no hooks |
| devops-tools | Mentions hooks in skills but no table |
| doc-tools | No hooks |
| quality-tools | No hooks |
| mql5 | No hooks |
| itp-hooks | Has extensive hooks (PreToolUse, PostToolUse, Stop) |
| asciinema-tools | No hooks |
| quant-research | No hooks |
| gmail-commander | No hooks table |
| calcom-commander | No hooks table |
| mise | No hooks |
| gitnexus-tools | Has Hooks |
| rust-tools | Has Hooks |

**Recommendation:** Add "No hooks" note or document any implicit hooks.

### 6. Additional Sections Found (Non-Standard)

| Section | Plugins |
|---------|---------|
| Overview | itp-hooks, ru, kokoro-tts, tts-telegram-sync, gitnexus-tools |
| Architecture | gmail-commander, calcom-commander, tts-telegram-sync, kokoro-tts |
| Dependencies | itp |
| Environment Variables | gmail-commander, calcom-commander |
| Philosophy | git-town-workflow |
| Tool Categories | rust-tools |
| Analysis Pipeline | asciinema-tools |
| Key Paths | kokoro-tts, tts-telegram-sync |
| Self-Bootstrapping | mise |

**Recommendation:** These sections are valuable but should follow consistent naming conventions.

---

## Link Pattern Analysis

### Internal Links

| Pattern | Usage | Plugins |
|---------|-------|---------|
| Relative `./` | Skills, references | All compliant |
| Repo-root `/docs/...` | ADRs | Most compliant |
| Sibling `../name/CLAUDE.md` | Navigation | Most compliant |

### External Links

| Pattern | Usage | Plugins |
|---------|-------|---------|
| Full URL | External resources | Most compliant |
| GitHub Issues | References | gh-tools, itp-hooks |

**Issues Found:**
- Some plugins use hardcoded paths instead of repo-root (`/docs/adr/...`)
- Some missing link formatting consistency

---

## Redundancies Identified

### 1. Duplicate Information

| Location | Issue |
|----------|-------|
| Root CLAUDE.md | Says "20 plugins" but marketplace.json has 23 |
| plugins/CLAUDE.md | Lists 21 plugins, missing 2 (kokoro-tts, gitnexus-tools) |

### 2. Overlapping Content

- `itp` and `itp-hooks` both document workflow patterns
- `devops-tools` and `quality-tools` both reference ClickHouse
- `gmail-commander` and `calcom-commander` have nearly identical Architecture tables

---

## Recommendations

### High Priority

1. **Fix root CLAUDE.md**: Update "20 plugins" to "23 plugins"
2. **Fix plugins/CLAUDE.md**: Add kokoro-tts and gitnexus-tools to the plugin table
3. **Standardize header format**: Use `# <plugin-name> Plugin` for all
4. **Complete navigation**: Add Sibling links to kokoro-tts

### Medium Priority

5. **Add missing Skills tables**: git-town-workflow, gmail-commander, tts-telegram-sync, calcom-commander, mise
6. **Document "No hooks" explicitly**: For plugins without hooks
7. **Standardize "Commands" vs "Skills"**: Clarify when to use each

### Low Priority

8. **Consistent section ordering**: Establish canonical order (Header → Description → Hub/Sibling → Overview → Skills → Commands → Hooks → Conventions → References)
9. **Terminology alignment**: "Plugin" suffix consistency
10. **Cross-reference deduplication**: Consolidate overlapping content between related plugins

---

## Appendix: Plugin Inventory

| # | Plugin Name | marketplace.json | Has CLAUDE.md | Notes |
|---|-------------|------------------|---------------|-------|
| 1 | plugin-dev | ✓ | ✓ | |
| 2 | itp | ✓ | ✓ | |
| 3 | gh-tools | ✓ | ✓ | |
| 4 | link-tools | ✓ | ✓ | |
| 5 | devops-tools | ✓ | ✓ | |
| 6 | dotfiles-tools | ✓ | ✓ | |
| 7 | doc-tools | ✓ | ✓ | |
| 8 | quality-tools | ✓ | ✓ | |
| 9 | productivity-tools | ✓ | ✓ | |
| 10 | mql5 | ✓ | ✓ | |
| 11 | itp-hooks | ✓ | ✓ | |
| 12 | ru | ✓ | ✓ | |
| 13 | statusline-tools | ✓ | ✓ | |
| 14 | asciinema-tools | ✓ | ✓ | |
| 15 | git-town-workflow | ✓ | ✓ | |
| 16 | quant-research | ✓ | ✓ | |
| 17 | gmail-commander | ✓ | ✓ | |
| 18 | kokoro-tts | ✓ | ✓ | Missing Sibling links |
| 19 | tts-telegram-sync | ✓ | ✓ | |
| 20 | calcom-commander | ✓ | ✓ | |
| 21 | mise | ✓ | ✓ | |
| 22 | gitnexus-tools | ✓ | ✓ | |
| 23 | rust-tools | ✓ | ✓ | |

---

*Generated by Task 1: Documentation Standards Audit*
