# Accessibility & Findability Review

**Task**: Task 8: Accessibility & Findability Review  
**Date**: 2026-03-02

---

## Executive Summary

This review synthesizes findings from Tasks 1, 5, and 6 to assess documentation accessibility and findability. The cc-skills ecosystem has strong foundational navigation (Hub+Sibling pattern at 87% compliance) but gaps in cross-referencing, unified search, and content discoverability.

**Key Findings:**
- **87%** of plugins follow Hub+Sibling navigation pattern
- **No unified skill index** - users must know plugin name to discover skills
- **4 plugins missing Skills sections** (kokoro-tts, mise, ru, tts-tg-sync)
- **1 orphaned plugin link** (kokoro-tts missing Sibling link)
- **Duplicate content** across 5+ plugins (1Password patterns)

---

## Accessibility Assessment

### 1. Navigation Structure

**Current State:**
- Hub-and-Spoke model with root CLAUDE.md as central hub
- 14 outbound links from root
- 27 outbound links from plugins/CLAUDE.md

**Findings from Task-1:**
| Metric | Compliance |
|--------|------------|
| Hub+Sibling navigation | 87% (20/23) |
| Skills tables | 78% (18/23) |
| Commands tables | 70% (16/23) |
| Hooks tables | 65% (15/23) |

**Accessibility Issues:**
- **kokoro-tts**: Missing Sibling link entirely
- **4 plugins**: Missing Skills sections (calcom-commander, git-town-workflow, gmail-commander, mise, ru, tts-tg-sync)
- **Header format inconsistencies**: Some use `# plugin-name Plugin`, others use `# plugin-name`

### 2. Link Integrity

**Broken Links Analysis:**
- Root CLAUDE.md: 14 links - all valid
- plugins/CLAUDE.md: 27 links to plugin CLAUDE.md files - all valid
- lychee configured but not integrated in CI

**Internal Cross-References:**
- Task-5 found: Hub-and-spoke model lacks depth in cross-referencing between spokes
- No systematic way to discover related skills across plugins

### 3. Search & Discovery

**Current Mechanisms:**
1. **Slash commands**: `/<skill-name>` - requires knowing skill name
2. **marketplace.json**: Plugin registry but no skill search
3. **Manual browsing**: Navigate through hub → plugin → skill

**Gaps Identified (Task-5):**
- No unified skill index
- No cross-plugin skill discovery
- No full-text search of documentation

### 4. Content Accessibility

**Duplicate Content Issues (Task-6):**
- 1Password documentation repeated in 5+ plugins
- Could be extracted to shared reference

**Missing Content:**
- 4 plugins without Skills sections
- Inconsistent Commands/Hooks tables

---

## Implementation Plan

### Phase 1: Fix Critical Accessibility Issues (Immediate)

| Issue | Fix | Priority |
|-------|-----|----------|
| kokoro-tts missing Sibling link | Add Sibling link to plugins/CLAUDE.md | Critical |
| 4 plugins missing Skills sections | Add Skills sections to calcom-commander, git-town-workflow, gmail-commander, mise, ru, tts-tg-sync | High |
| Header format inconsistencies | Standardize to `# <plugin-name> Plugin` format | Medium |

### Phase 2: Improve Findability (Short-Term)

| Improvement | Action | Priority |
|-------------|--------|----------|
| Unified skill index | Generate index from marketplace.json + skills/ | High |
| Cross-reference links | Add "Related Skills" sections in SKILL.md | Medium |
| Lychee CI integration | Add to pre-commit or GitHub Actions | Medium |

### Phase 3: Enhanced Discovery (Long-Term)

| Enhancement | Description | Priority |
|------------|-------------|----------|
| Global search | Full-text search across all docs | Low |
| Skill recommendations | Auto-suggest related skills based on usage | Low |
| Interactive navigation | TUI for skill discovery | Low |

---

## Related Findings

- **Task-1**: 87% Hub+Sibling compliance, structural inconsistencies
- **Task-5**: No unified skill index, hub-and-spoke lacks cross-references
- **Task-6**: Duplicate 1Password content, 4 plugins missing Skills sections

---

## Recommendations Summary

1. **Immediate**: Fix kokoro-tts Sibling link
2. **Immediate**: Add Skills sections to 4 plugins
3. **Short-term**: Generate unified skill index
4. **Short-term**: Add lychee to CI pipeline
5. **Long-term**: Consider full-text search solution
